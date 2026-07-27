//
//  SchemaOrgRecipeJSONLDExporter.swift
//  Salty
//
//  Serializes a `Recipe` to schema.org/Recipe JSON-LD, the inverse of SchemaOrgRecipeJSONLDImporter,
//  with the field mapping kept symmetric so exported files re-import cleanly.
//
//  This produces standards-shaped output for sharing/archiving/interop with other recipe tools.
//  For a lossless Salty-to-Salty round-trip, use the native `.saltyRecipe` export instead: schema.org
//  has no representation for some Salty concepts, so the following are intentionally NOT exported:
//  section headings (ingredient & direction), the ingredient `isMain` flag, difficulty,
//  rating, locally-stored image bytes, and added sugars (from nutrition).
//

import Foundation

struct SchemaOrgRecipeJSONLDExporter {

    /// Library metadata resolved from the database by the caller; the exporter itself stays DB-free so
    /// it can be unit-tested in isolation.
    struct LibraryMetadata {
        var courseName: String?
        var categoryNames: [String]
        var tagNames: [String]

        init(courseName: String? = nil, categoryNames: [String] = [], tagNames: [String] = []) {
            self.courseName = courseName
            self.categoryNames = categoryNames
            self.tagNames = tagNames
        }
    }

    // MARK: - Public API

    /// A single schema.org Recipe object. Includes `@context`, so it is valid stand-alone JSON-LD.
    func jsonObject(for recipe: Recipe, metadata: LibraryMetadata = LibraryMetadata()) -> [String: Any] {
        var dict: [String: Any] = [
            "@context": "https://schema.org",
            "@type": "Recipe",
            "name": recipe.name,
        ]

        if !recipe.introduction.isEmpty { dict["description"] = recipe.introduction }
        if !recipe.source.isEmpty {
            dict["author"] = ["@type": "Person", "name": recipe.source]
        }
        // On import, a source URL is stored in `sourceDetails`; only emit `url` when it really is one
        // (free-text source details like "p. 12" have no standard schema.org home).
        if isURL(recipe.sourceDetails) { dict["url"] = recipe.sourceDetails }

        dict["datePublished"] = iso8601Date(recipe.createdDate)

        if let yieldValue = yieldString(recipe) { dict["recipeYield"] = yieldValue }

        let ingredientLines = recipe.ingredients.filter { !$0.isHeading }.map(\.text)
        if !ingredientLines.isEmpty { dict["recipeIngredient"] = ingredientLines }

        let steps = recipe.directions
            .filter { !($0.isHeading ?? false) }
            .map { ["@type": "HowToStep", "text": $0.text] }
        if !steps.isEmpty { dict["recipeInstructions"] = steps }

        for time in recipe.preparationTimes {
            guard let iso = iso8601Duration(from: time.timeString) else { continue }
            switch time.type.lowercased() {
            case "prep": dict["prepTime"] = iso
            case "cook": dict["cookTime"] = iso
            case "total": dict["totalTime"] = iso
            default: break
            }
        }

        if let nutrition = nutritionObject(recipe.nutrition) { dict["nutrition"] = nutrition }

        // Salty's course is the closest match to schema.org's recipeCategory ("appetizer", "entree"…);
        // tags + categories become free-text keywords.
        if let courseName = metadata.courseName, !courseName.isEmpty {
            dict["recipeCategory"] = courseName
        }
        let keywords = (metadata.tagNames + metadata.categoryNames).filter { !$0.isEmpty }
        if !keywords.isEmpty { dict["keywords"] = keywords.joined(separator: ", ") }

        return dict
    }

    /// JSON-LD `Data` for a single recipe (one object).
    func data(for recipe: Recipe, metadata: LibraryMetadata = LibraryMetadata()) throws -> Data {
        try serialize(jsonObject(for: recipe, metadata: metadata))
    }

    /// JSON-LD `Data` for several recipes: a single object when there is one, otherwise an array of
    /// objects (both shapes are accepted by SchemaOrgRecipeJSONLDImporter).
    func data(for recipes: [(recipe: Recipe, metadata: LibraryMetadata)]) throws -> Data {
        let objects = recipes.map { jsonObject(for: $0.recipe, metadata: $0.metadata) }
        if objects.count == 1 { return try serialize(objects[0]) }
        return try serialize(objects)
    }

    // MARK: - Serialization

    private func serialize(_ object: Any) throws -> Data {
        try JSONSerialization.data(
            withJSONObject: object,
            options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        )
    }

    // MARK: - Field helpers

    private func yieldString(_ recipe: Recipe) -> String? {
        if !recipe.yield.isEmpty { return recipe.yield }
        if let servings = recipe.servings { return String(servings) }
        return nil
    }

    private func isURL(_ string: String) -> Bool {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        return trimmed.hasPrefix("http://") || trimmed.hasPrefix("https://")
    }

    private func iso8601Date(_ date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.string(from: date)
    }

    /// Builds a schema.org NutritionInformation object with unit-suffixed string values matching what the
    /// importer parses back. Returns nil when there is nothing to emit.
    private func nutritionObject(_ nutrition: NutritionInformation?) -> [String: Any]? {
        guard let n = nutrition else { return nil }
        var dict: [String: Any] = ["@type": "NutritionInformation"]

        if let servingSize = n.servingSize, !servingSize.isEmpty { dict["servingSize"] = servingSize }
        if let calories = n.calories { dict["calories"] = "\(number(calories)) calories" }

        func grams(_ key: String, _ value: Double?) { if let v = value { dict[key] = "\(number(v)) g" } }
        func milligrams(_ key: String, _ value: Double?) { if let v = value { dict[key] = "\(number(v)) mg" } }
        func micrograms(_ key: String, _ value: Double?) { if let v = value { dict[key] = "\(number(v)) µg" } }

        grams("proteinContent", n.protein)
        grams("carbohydrateContent", n.carbohydrates)
        grams("fatContent", n.fat)
        grams("saturatedFatContent", n.saturatedFat)
        grams("transFatContent", n.transFat)
        grams("fiberContent", n.fiber)
        grams("sugarContent", n.sugar)
        milligrams("sodiumContent", n.sodium)
        milligrams("cholesterolContent", n.cholesterol)
        milligrams("calciumContent", n.calcium)
        milligrams("ironContent", n.iron)
        milligrams("potassiumContent", n.potassium)
        milligrams("vitaminCContent", n.vitaminC)
        micrograms("vitaminDContent", n.vitaminD)
        micrograms("vitaminAContent", n.vitaminA)

        // Only @type present → no real data.
        return dict.count > 1 ? dict : nil
    }

    /// Formats a measurement, dropping a trailing ".0" so whole numbers read cleanly ("9" not "9.0").
    private func number(_ value: Double) -> String {
        value == value.rounded() ? String(Int(value)) : String(value)
    }

    /// Converts a human-readable duration ("15 min", "1 hr 30 min") to an ISO 8601 duration ("PT15M",
    /// "PT1H30M"). Returns nil when nothing parseable is found (the field is then omitted).
    private func iso8601Duration(from human: String) -> String? {
        let lower = human.lowercased()
        let hours = firstInt(in: lower, pattern: #"(\d+)\s*(?:hours?|hrs?|h)\b"#)
        let minutes = firstInt(in: lower, pattern: #"(\d+)\s*(?:minutes?|mins?|m)\b"#)

        guard hours != nil || minutes != nil else { return nil }
        let h = hours ?? 0, m = minutes ?? 0
        guard h > 0 || m > 0 else { return nil }

        var result = "PT"
        if h > 0 { result += "\(h)H" }
        if m > 0 { result += "\(m)M" }
        return result
    }

    /// Returns the first capture-group-1 integer for `pattern` in `string`, or nil.
    private func firstInt(in string: String, pattern: String) -> Int? {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return nil }
        let range = NSRange(string.startIndex..., in: string)
        guard let match = regex.firstMatch(in: string, range: range),
              match.numberOfRanges > 1,
              let groupRange = Range(match.range(at: 1), in: string) else {
            return nil
        }
        return Int(string[groupRange])
    }
}
