//
//  CroutonImportRecipe.swift
//  SaltyCore
//
//  Created by Robert on 8/15/26.
//

import Foundation
import UUIDV7

/// Represents data from a Crouton export file (`.crumb`), which is a single JSON object per recipe.
///
/// Crouton publishes no schema for `.crumb`, so this model was derived from a real export. Everything
/// past `name` is optional: a file that omits keys we expect, or carries keys we've never seen, still
/// imports rather than failing outright.
///
/// What Crouton stores that Salty deliberately drops:
/// - `folderIDs` — opaque UUIDs with no folder names anywhere in the file, so nothing useful to map.
/// - `sourceImage` — a 16–48px favicon of the source site, not a recipe photo.
/// - `defaultScale` / `isPublicRecipe` / per-object `uuid`s — Crouton bookkeeping with no Salty analogue.
public struct CroutonImportRecipe: Decodable, Sendable {
    public var name = ""
    public var notes: String?
    /// Usually a bare URL, but Crouton lets the user type anything here ("Adapted from http://…").
    public var webLink: String?
    public var sourceName: String?
    public var serves: Int?
    public var rating: Int?
    /// "Easy" / "Medium" / "Hard" in the exports seen so far.
    public var rawDifficulty: String?
    /// Preparation time in minutes (Crouton's "Duration").
    public var duration: Int?
    /// Cooking time in minutes (Crouton's "Cooking Duration").
    public var cookingDuration: Int?
    /// Free-form nutrition text. The misspelled key is Crouton's, not a typo here.
    public var nutritionalInfo: String?
    public var tags: [String]?
    public var steps: [CroutonStep]?
    public var ingredients: [CroutonIngredientEntry]?
    /// Base64-encoded JPEGs. Decoded leniently rather than as `[Data]` so one malformed entry can't
    /// fail the whole recipe.
    public var images: [String]?

    public enum CodingKeys: String, CodingKey {
        case name
        case notes
        case webLink
        case sourceName
        case serves
        case rating
        case rawDifficulty
        case duration
        case cookingDuration
        case nutritionalInfo = "neutritionalInfo"
        case tags
        case steps
        case ingredients
        case images
    }

    public struct CroutonStep: Decodable, Sendable {
        public var order: Int?
        public var step: String?
        /// Crouton's directions can carry headings ("Prepare filling"); these map to Salty headings.
        public var isSection: Bool?
    }

    public struct CroutonIngredientEntry: Decodable, Sendable {
        public var order: Int?
        public var quantity: CroutonQuantity?
        public var ingredient: CroutonIngredientName?
    }

    public struct CroutonQuantity: Decodable, Sendable {
        public var amount: Double?
        /// Upper bound of a range ("2 – 2 1/2 lb"), when the user entered one.
        public var secondaryAmount: Double?
        public var quantityType: String?
    }

    public struct CroutonIngredientName: Decodable, Sendable {
        public var name: String?
    }

    /// Converts CroutonImportRecipe to a Recipe object.
    /// - Parameter imageData: receives the recipe photo, if any. As with the MacGourmet import, the
    /// image can't be attached here — `Recipe.setImage` needs the recipe to exist in the database
    /// first — so the caller inserts the recipe and then saves this data.
    /// - Parameter tags: receives the Crouton tag names, which likewise need the recipe row to exist
    /// before the join rows can be written.
    /// - Returns: Recipe object with (nearly) matching data from the Crouton recipe
    public func convertToRecipe(imageData: inout Data?, tags parsedTags: inout [String]?) -> Recipe {
        var recipeNotes: [Note] = []
        if let noteText = notes?.trimmingCharacters(in: .whitespacesAndNewlines), !noteText.isEmpty {
            recipeNotes.append(Note(id: UUIDV7().uuidString, title: "Notes", content: noteText))
        }
        // Crouton's nutrition field is free text ("Calories: 331 Fat: 7.5g …"), not the labelled values
        // `NutritionInformation` expects, so it's kept verbatim as a note rather than guess-parsed.
        if let nutritionText = nutritionalInfo?.trimmingCharacters(in: .whitespacesAndNewlines), !nutritionText.isEmpty {
            recipeNotes.append(Note(id: UUIDV7().uuidString, title: "Nutrition", content: nutritionText))
        }

        let recipe = Recipe(
            id: UUIDV7().uuidString,
            name: name,
            createdDate: Date(),
            lastModifiedDate: Date(),
            lastPrepared: nil,
            source: sourceName ?? "",
            sourceDetails: webLink ?? "",
            introduction: "",
            difficulty: Self.difficulty(fromRawDifficulty: rawDifficulty),
            rating: rating.flatMap { Rating(rawValue: min(max($0, 0), 5)) } ?? .notSet,
            imageFilename: nil,
            imageThumbnailData: nil,
            isFavorite: false,
            wantToMake: false,
            yield: "",
            servings: (serves ?? 0) > 0 ? serves : nil,
            directions: Self.directions(from: steps),
            ingredients: Self.ingredients(from: ingredients),
            notes: recipeNotes,
            preparationTimes: Self.preparationTimes(prepMinutes: duration, cookMinutes: cookingDuration)
        )

        imageData = Self.bestImageData(fromBase64: images)

        let cleanTags = (tags ?? [])
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        parsedTags = cleanTags.isEmpty ? nil : cleanTags

        return recipe
    }

    // MARK: - Field conversion

    static func difficulty(fromRawDifficulty rawDifficulty: String?) -> Difficulty {
        switch rawDifficulty?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "easy": return .easy
        case "medium": return .medium
        case "hard", "difficult": return .difficult
        default: return .notSet
        }
    }

    static func directions(from steps: [CroutonStep]?) -> [Direction] {
        ordered(steps ?? [], by: \.order).compactMap { step in
            let text = (step.step ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { return nil }
            return Direction(id: UUIDV7().uuidString, isHeading: step.isSection ?? false, text: text)
        }
    }

    static func ingredients(from entries: [CroutonIngredientEntry]?) -> [Ingredient] {
        ordered(entries ?? [], by: \.order).compactMap { entry in
            let name = (entry.ingredient?.name ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !name.isEmpty else { return nil }

            let isHeading = CroutonQuantityType.isSection(rawType: entry.quantity?.quantityType)
            return Ingredient(
                id: UUIDV7().uuidString,
                isHeading: isHeading,
                isMain: false,
                text: isHeading ? name : ingredientText(name: name, quantity: entry.quantity)
            )
        }
    }

    /// Rebuilds Crouton's split quantity/unit/name into the single line Salty stores.
    static func ingredientText(name: String, quantity: CroutonQuantity?) -> String {
        guard let quantity else { return name }
        let unit = CroutonQuantityType.unitText(forRawType: quantity.quantityType ?? "", amount: quantity.amount)
        return [amountText(for: quantity), unit, name]
            .filter { !$0.isEmpty }
            .joined(separator: " ")
    }

    static func amountText(for quantity: CroutonQuantity) -> String {
        guard let amount = quantity.amount, amount > 0 else { return "" }
        let low = IngredientScaler.formatScaledAmount(amount)
        // An unspaced hyphen is the range form Salty's own scaler reads and writes, so a range imported
        // from Crouton still scales correctly in the app.
        if let high = quantity.secondaryAmount, high > amount {
            return "\(low)-\(IngredientScaler.formatScaledAmount(high))"
        }
        return low
    }

    static func preparationTimes(prepMinutes: Int?, cookMinutes: Int?) -> [PreparationTime] {
        [("Prep", prepMinutes), ("Cook", cookMinutes)].compactMap { type, minutes in
            guard let minutes, minutes > 0 else { return nil }
            return PreparationTime(id: UUIDV7().uuidString, type: type, timeString: minutesText(minutes))
        }
    }

    /// Renders whole minutes the way the other importers do ("45 min", "1 hr", "1 hr 30 min").
    static func minutesText(_ minutes: Int) -> String {
        let hours = minutes / 60
        let remainder = minutes % 60
        var parts: [String] = []
        if hours > 0 { parts.append("\(hours) hr") }
        if remainder > 0 || hours == 0 { parts.append("\(remainder) min") }
        return parts.joined(separator: " ")
    }

    /// Picks the recipe photo out of Crouton's image array.
    ///
    /// Crouton writes a 280×280 thumbnail first and the full-size photo after it, so taking the first
    /// entry would import a postage stamp. Taking the largest payload gets the real photo whether the
    /// file holds one image or two, and skips any entry whose base64 is malformed.
    static func bestImageData(fromBase64 images: [String]?) -> Data? {
        (images ?? [])
            .compactMap { Data(base64Encoded: $0, options: .ignoreUnknownCharacters) }
            .max { $0.count < $1.count }
    }

    /// Sorts by Crouton's explicit `order` field, falling back to file order for entries that omit it.
    private static func ordered<T>(_ items: [T], by order: KeyPath<T, Int?>) -> [T] {
        items.enumerated()
            .sorted { ($0.element[keyPath: order] ?? $0.offset) < ($1.element[keyPath: order] ?? $1.offset) }
            .map(\.element)
    }
}
