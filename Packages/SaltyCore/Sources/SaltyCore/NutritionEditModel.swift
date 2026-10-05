//
//  NutritionEditModel.swift
//  SaltyCore
//
//  What a nutrition editor edits: one text per amount, as typed, plus the serving size. The editor
//  used to keep thirty-five pieces of state (a text and a validity flag per field) and the rules for
//  turning them back into a `NutritionInformation` in the view, which is how amounts of a thousand or
//  more were silently dropped for a while without a test noticing. Every front end needs these same
//  rules, so they live here, on a value any of them can hold and any test can drive.
//
//  Text goes through `NutritionValueText`, so what is shown and what is read back agree on the
//  user's locale.
//

import Foundation

public struct NutritionEditModel: Equatable, Sendable {

    /// The amounts, in the order an editor shows them.
    public enum Field: String, CaseIterable, Hashable, Sendable {
        case calories
        case protein, carbohydrates, fat, saturatedFat, transFat, fiber, sugar, addedSugar
        case sodium, cholesterol
        case vitaminD, calcium, iron, potassium, vitaminA, vitaminC

        /// How the amount is measured; nil for calories, which carry no unit.
        public var unit: Unit? {
            switch self {
            case .calories: nil
            case .protein, .carbohydrates, .fat, .saturatedFat, .transFat, .fiber, .sugar, .addedSugar: .grams
            case .sodium, .cholesterol, .calcium, .iron, .potassium, .vitaminC: .milligrams
            case .vitaminD, .vitaminA: .micrograms
            }
        }

        /// The group an editor files the field under.
        public var section: Section {
            switch self {
            case .calories: .general
            case .protein, .carbohydrates, .fat, .saturatedFat, .transFat, .fiber, .sugar, .addedSugar: .macronutrients
            case .sodium, .cholesterol: .otherNutrients
            case .vitaminD, .calcium, .iron, .potassium, .vitaminA, .vitaminC: .vitaminsAndMinerals
            }
        }

        /// Where the amount lives on the stored value.
        var keyPath: WritableKeyPath<NutritionInformation, Double?> {
            switch self {
            case .calories: \.calories
            case .protein: \.protein
            case .carbohydrates: \.carbohydrates
            case .fat: \.fat
            case .saturatedFat: \.saturatedFat
            case .transFat: \.transFat
            case .fiber: \.fiber
            case .sugar: \.sugar
            case .addedSugar: \.addedSugar
            case .sodium: \.sodium
            case .cholesterol: \.cholesterol
            case .vitaminD: \.vitaminD
            case .calcium: \.calcium
            case .iron: \.iron
            case .potassium: \.potassium
            case .vitaminA: \.vitaminA
            case .vitaminC: \.vitaminC
            }
        }
    }

    public enum Unit: Sendable {
        case grams, milligrams, micrograms
    }

    public enum Section: CaseIterable, Sendable {
        case general, macronutrients, otherNutrients, vitaminsAndMinerals

        /// The fields shown under this heading, in order. Serving size is text, not an amount, and
        /// sits above the general fields in every editor.
        public var fields: [Field] {
            Field.allCases.filter { $0.section == self }
        }
    }

    /// Free text: "1 cup", "2 slices".
    public var servingSize: String
    private var texts: [Field: String]
    /// The locale the texts are written and read in.
    public let locale: Locale
    /// The value being edited, so a save keeps its identity rather than minting a new one -- a new id
    /// on every save made an untouched editor look like a change.
    private let original: NutritionInformation?

    /// Starts from `nutrition` (or blank fields for nil), showing each amount the way `locale` writes
    /// numbers.
    public init(_ nutrition: NutritionInformation?, locale: Locale = .current) {
        self.original = nutrition
        self.locale = locale
        self.servingSize = nutrition?.servingSize ?? ""
        var texts: [Field: String] = [:]
        for field in Field.allCases {
            texts[field] = NutritionValueText.text(for: nutrition?[keyPath: field.keyPath], locale: locale)
        }
        self.texts = texts
    }

    // MARK: - Editing

    /// The text in a field, exactly as typed.
    public subscript(field: Field) -> String {
        get { texts[field] ?? "" }
        set { texts[field] = newValue }
    }

    /// The amount a field holds: nil when it is blank or not a number.
    public func value(of field: Field) -> Double? {
        NutritionValueText.value(from: self[field], locale: locale)
    }

    /// Whether the field is blank or reads as a number.
    public func isValid(_ field: Field) -> Bool {
        NutritionValueText.isValid(self[field], locale: locale)
    }

    /// Fields holding text that isn't a number. A save with any of these would lose what was typed,
    /// so an editor disables Save while this is non-empty.
    public var invalidFields: Set<Field> {
        Set(Field.allCases.filter { !isValid($0) })
    }

    public var hasInvalidFields: Bool {
        !invalidFields.isEmpty
    }

    /// Whether every field, serving size included, is blank.
    public var isBlank: Bool {
        servingSize.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            && Field.allCases.allSatisfy { self[$0].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    // MARK: - Result

    /// The value to store: nil when every field is blank, otherwise the amounts read from the texts
    /// (a field that isn't a number reads as nil) under the original's id.
    public var nutrition: NutritionInformation? {
        guard !isBlank else { return nil }
        var result = original ?? NutritionInformation()
        let trimmedServing = servingSize.trimmingCharacters(in: .whitespacesAndNewlines)
        result.servingSize = trimmedServing.isEmpty ? nil : trimmedServing
        for field in Field.allCases {
            result[keyPath: field.keyPath] = value(of: field)
        }
        return result
    }

    /// Whether saving would store something different from what the editor started with.
    public var hasChanges: Bool {
        nutrition != original
    }
}
