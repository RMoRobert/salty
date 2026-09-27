//
//  SchemaOrgRecipeReader.swift
//  SaltyCore
//
//  Purpose: One schema.org `Recipe` node, read into a draft Salty recipe field by field, following
//  salty-contract SPEC.md §8.2-8.3 (WEB-010 to WEB-031). The page's other blocks are reachable through
//  the dataset, for node references.
//

import Foundation
import UUIDV7

struct SchemaOrgRecipeReader {

    let dataset: JSONLDDataset

    /// Where the page came from, when that is an http(s) address: the base for relative addresses
    /// (WEB-011) and the source of a recipe that declares no `url` (WEB-020).
    let pageURL: String?

    /// WEB-008.
    static let maxFieldLength = 20_000
    static let maxListItems = 1_000

    init(dataset: JSONLDDataset, pageURL: String?) {
        self.dataset = dataset
        if let pageURL, let scheme = URL(string: pageURL)?.scheme?.lowercased(), scheme == "http" || scheme == "https" {
            self.pageURL = pageURL
        } else {
            self.pageURL = nil
        }
    }

    /// The recipe `node` describes: a draft with fresh ids, stamped now, nothing stored (WEB-031).
    func recipe(from node: JSONLDValue, now: Date) -> SchemaOrgRecipeJSONLDImporter.ScannedRecipe {
        let yield = yieldValues(node)
        let nutritionNode = dataset.values(node, "nutrition").first { $0.fields != nil }
        let servingSize = nutritionNode.flatMap { text($0, "servingSize") }

        let recipe = Recipe(
            id: UUIDV7().uuidString,
            name: text(node, "name") ?? "",
            createdDate: now,
            lastModifiedDate: now,
            lastPrepared: nil,
            source: author(node),
            sourceDetails: address(text(node, "url")) ?? pageURL ?? "",
            introduction: text(node, "description") ?? "",
            difficulty: .notSet,
            // Not the site's aggregateRating: the app's rating is the user's own (WEB-030).
            rating: .notSet,
            imageFilename: nil,
            imageThumbnailData: nil,
            isFavorite: false,
            wantToMake: false,
            yield: yield.text,
            servings: yield.servings(servingSize: servingSize),
            directions: directions(node),
            ingredients: ingredients(node),
            notes: [],
            preparationTimes: preparationTimes(node),
            nutrition: nutritionNode.flatMap(nutrition)
        )
        return SchemaOrgRecipeJSONLDImporter.ScannedRecipe(recipe: recipe, imageURL: imageURL(node))
    }

    // MARK: - Text and addresses

    /// WEB-010: the first of the property's values that is non-empty text after cleaning.
    func text(_ node: JSONLDValue, _ property: String) -> String? {
        for value in dataset.values(node, property) {
            if let text = text(of: value), !text.isEmpty {
                return text
            }
        }
        return nil
    }

    /// A string, or a bare number (WEB-L03), cleaned; nil for anything else.
    private func text(of value: JSONLDValue) -> String? {
        value.primitiveText.map(clean)
    }

    /// WEB-L02 and WEB-008: character references decoded once (strictly), whitespace trimmed after
    /// decoding, and the result clamped.
    private func clean(_ raw: String) -> String {
        let decoded = HTMLEntities.decode(raw).trimmingCharacters(in: .whitespacesAndNewlines)
        return decoded.count > Self.maxFieldLength ? String(decoded.prefix(Self.maxFieldLength)) : decoded
    }

    /// WEB-011: `text` as an http(s) address, resolved against the page when it is relative.
    private func address(_ text: String?) -> String? {
        guard let text, !text.isEmpty else { return nil }
        if let scheme = URL(string: text)?.scheme?.lowercased() {
            return scheme == "http" || scheme == "https" ? text : nil
        }
        guard let pageURL, let base = URL(string: pageURL),
              let resolved = URL(string: text, relativeTo: base)?.absoluteURL,
              let scheme = resolved.scheme?.lowercased(), scheme == "http" || scheme == "https"
        else {
            return nil
        }
        return resolved.absoluteString
    }

    // MARK: - Fields

    /// WEB-021: a Person or Organization by its name, or text; several joined in order.
    private func author(_ node: JSONLDValue) -> String {
        dataset.values(node, "author")
            .compactMap { value in value.fields != nil ? text(value, "name") : text(of: value) }
            .filter { !$0.isEmpty }
            .joined(separator: ", ")
    }

    /// WEB-022: the first value that yields an address -- a URL, or a MediaObject's `contentUrl` (the
    /// file itself), else its `url`.
    private func imageURL(_ node: JSONLDValue) -> String? {
        for value in dataset.values(node, "image") {
            let found = value.fields != nil
                ? address(text(value, "contentUrl")) ?? address(text(value, "url"))
                : address(text(of: value))
            if let found {
                return found
            }
        }
        return nil
    }

    /// WEB-023: `recipeYield`, else the inherited HowTo `yield`.
    private func yieldValues(_ node: JSONLDValue) -> SchemaOrgYield {
        let property = dataset.has(node, "recipeYield") ? "recipeYield" : "yield"
        return SchemaOrgYield(values: dataset.values(node, property).compactMap(yieldValue))
    }

    private func yieldValue(_ value: JSONLDValue) -> SchemaOrgYield.Value? {
        switch value {
        case .string, .number:
            guard let text = text(of: value), !text.isEmpty else { return nil }
            let number = Double(text)
            let isNumber = number != nil && text.allSatisfy { $0.isASCII && ($0.isNumber || $0 == ".") }
            return SchemaOrgYield.Value(text: text, isNumber: isNumber, servingsCount: isNumber ? wholeCount(number) : nil)
        case .object:
            let unit = text(value, "unitText") ?? ""
            if let amount = text(value, "value") {
                let joined = unit.isEmpty ? amount : "\(amount) \(unit)"
                let counts = unit.isEmpty || SchemaOrgYield.isServingsUnit(unit)
                return SchemaOrgYield.Value(text: joined, isNumber: unit.isEmpty && Double(amount) != nil,
                                            servingsCount: counts ? wholeCount(Double(amount)) : nil)
            }
            if let low = text(value, "minValue"), let high = text(value, "maxValue") {
                let range = "\(low)\u{2013}\(high)"
                return SchemaOrgYield.Value(text: unit.isEmpty ? range : "\(range) \(unit)", isNumber: false, servingsCount: nil)
            }
            return nil
        default:
            return nil
        }
    }

    private func wholeCount(_ number: Double?) -> Int? {
        guard let number, number > 0, number.rounded() == number, number < Double(Int32.max) else { return nil }
        return Int(number)
    }

    /// WEB-025: `recipeIngredient`, else the superseded `ingredients`.
    private func ingredients(_ node: JSONLDValue) -> [Ingredient] {
        let property = dataset.has(node, "recipeIngredient") ? "recipeIngredient" : "ingredients"
        return dataset.values(node, property)
            .flatMap(ingredientTexts)
            .filter { !$0.isEmpty }
            .prefix(Self.maxListItems)
            .map { Ingredient(id: UUIDV7().uuidString, isHeading: false, isMain: false, text: $0) }
    }

    private func ingredientTexts(_ value: JSONLDValue) -> [String] {
        guard value.fields != nil else {
            return text(of: value).map { [$0] } ?? []
        }
        if dataset.has(value, "itemListElement") {
            return dataset.values(value, "itemListElement").flatMap(ingredientTexts)
        }
        if dataset.hasType(value, "ListItem") || dataset.has(value, "item") {
            let items = dataset.values(value, "item")
            return items.isEmpty ? (text(value, "name").map { [$0] } ?? []) : items.flatMap(ingredientTexts)
        }
        if dataset.hasType(value, "PropertyValue") || dataset.has(value, "value") {
            let unit = text(value, "unitText") ?? text(value, "unitCode").flatMap { Self.unitCodes[$0.uppercased()] }
            return [[text(value, "value"), unit, text(value, "name")]
                .compactMap { $0 }
                .filter { !$0.isEmpty }
                .joined(separator: " ")]
        }
        return text(value, "name").map { [$0] } ?? []
    }

    /// The UN/CEFACT common codes a kitchen measure is likely to use (WEB-025).
    private static let unitCodes = [
        "G21": "cup", "G24": "tablespoon", "G25": "teaspoon", "GRM": "g", "KGM": "kg",
        "MLT": "ml", "LTR": "l", "ONZ": "oz", "LBR": "lb",
    ]

    /// WEB-026: `recipeInstructions`, else the inherited HowTo `step`. Sections become heading rows.
    private func directions(_ node: JSONLDValue) -> [Direction] {
        let property = dataset.has(node, "recipeInstructions") ? "recipeInstructions" : "step"
        var rows: [Direction] = []

        func add(_ text: String?, heading: Bool) {
            guard rows.count < Self.maxListItems, let text, !text.isEmpty else { return }
            rows.append(Direction(id: UUIDV7().uuidString, isHeading: heading, text: text))
        }

        func walk(_ items: [JSONLDValue]) {
            for item in inPositionOrder(items) {
                visit(item)
            }
        }

        func visit(_ value: JSONLDValue) {
            switch value {
            case .string, .number:
                add(text(of: value), heading: false)
            case .array(let items):
                walk(items)
            case .object:
                if dataset.hasType(value, "HowToSection") {
                    add(text(value, "name"), heading: true)
                    walk(dataset.values(value, "itemListElement"))
                } else if dataset.hasType(value, "HowToStep") {
                    let parts = dataset.values(value, "itemListElement")
                    if parts.isEmpty {
                        add(text(value, "text") ?? text(value, "name"), heading: false)
                    } else {
                        walk(parts)
                    }
                } else if dataset.has(value, "itemListElement") {
                    walk(dataset.values(value, "itemListElement"))
                } else if dataset.hasType(value, "ListItem") || dataset.has(value, "item") {
                    let items = dataset.values(value, "item")
                    if items.isEmpty {
                        add(text(value, "text") ?? text(value, "name"), heading: false)
                    } else {
                        walk(items)
                    }
                } else {
                    add(text(value, "text") ?? text(value, "name"), heading: false)
                }
            default:
                break
            }
        }

        walk(dataset.values(node, property))
        return rows
    }

    /// When every item carries a numeric `position`, those items in that order (stable); otherwise as
    /// written. JSON-LD arrays are formally unordered, and `position` is how a list says its order.
    private func inPositionOrder(_ items: [JSONLDValue]) -> [JSONLDValue] {
        let positions = items.map { item -> Double? in
            guard item.fields != nil else { return nil }
            return dataset.values(item, "position").lazy.compactMap { $0.primitiveText.flatMap { Double($0) } }.first
        }
        guard !items.isEmpty, positions.allSatisfy({ $0 != nil }) else { return items }
        return zip(items, positions).enumerated()
            .sorted { ($0.element.1 ?? 0, $0.offset) < ($1.element.1 ?? 0, $1.offset) }
            .map(\.element.0)
    }

    /// WEB-027 and WEB-028.
    private func preparationTimes(_ node: JSONLDValue) -> [PreparationTime] {
        let cook = dataset.has(node, "cookTime") ? "cookTime" : "performTime"
        return [("prepTime", "Prep"), (cook, "Cook"), ("totalTime", "Total")].compactMap { property, label in
            text(node, property).map {
                PreparationTime(id: UUIDV7().uuidString, type: label, timeString: SchemaOrgDuration.display($0))
            }
        }
    }

    /// WEB-029: each field in the unit Salty stores it in; nil when nothing in the block is usable.
    private func nutrition(_ block: JSONLDValue) -> NutritionInformation? {
        func amount(_ property: String, _ unit: NutritionAmount.Unit) -> Double? {
            dataset.values(block, property).lazy.compactMap { value -> Double? in
                if case .string(let raw) = value {
                    return NutritionAmount.value(.string(clean(raw)), in: unit)
                }
                return NutritionAmount.value(value, in: unit)
            }.first
        }

        let information = NutritionInformation(
            servingSize: text(block, "servingSize"),
            calories: amount("calories", .kilocalories),
            protein: amount("proteinContent", .grams),
            carbohydrates: amount("carbohydrateContent", .grams),
            fat: amount("fatContent", .grams),
            saturatedFat: amount("saturatedFatContent", .grams),
            transFat: amount("transFatContent", .grams),
            fiber: amount("fiberContent", .grams),
            sugar: amount("sugarContent", .grams),
            sodium: amount("sodiumContent", .milligrams),
            cholesterol: amount("cholesterolContent", .milligrams),
            // Not schema.org; read because Salty has the fields and a page that publishes them means them.
            vitaminD: amount("vitaminDContent", .micrograms),
            calcium: amount("calciumContent", .milligrams),
            iron: amount("ironContent", .milligrams),
            potassium: amount("potassiumContent", .milligrams),
            vitaminA: amount("vitaminAContent", .micrograms),
            vitaminC: amount("vitaminCContent", .milligrams)
        )
        // schema.org's unsaturatedFatContent has no Salty field to go in; see SPEC.md WEB-029's known gap.
        return information == NutritionInformation(id: information.id) ? nil : information
    }
}
