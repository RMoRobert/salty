//
//  SchemaOrgRecipeJSONLDExporterTests.swift
//  SaltyTests
//
//  Verifies the schema.org/Recipe JSON-LD exporter: the emitted shape, and an end-to-end round-trip
//  back through SchemaOrgRecipeJSONLDImporter (proving the two stay symmetric). Both the exporter and
//  importer are pure (no database / StructuredQueries), so these are safe to run from the test bundle.
//

import Testing
import Foundation
@testable import Salty

struct SchemaOrgRecipeJSONLDExporterTests {

    private let exporter = SchemaOrgRecipeJSONLDExporter()

    /// A representative recipe whose fields all map cleanly to schema.org (no headings, URL source).
    private func sampleRecipe() -> Recipe {
        Recipe(
            id: "r1",
            name: "Banana Bread",
            createdDate: Date(timeIntervalSince1970: 1_700_000_000),
            lastModifiedDate: Date(timeIntervalSince1970: 1_700_000_000),
            source: "Jane Cook",
            sourceDetails: "https://example.com/banana-bread",
            introduction: "A moist, easy loaf.",
            yield: "1 loaf",
            servings: 8,
            directions: [
                Direction(id: "d1", isHeading: false, text: "Mash the bananas."),
                Direction(id: "d2", isHeading: false, text: "Bake 60 minutes."),
            ],
            ingredients: [
                Ingredient(id: "i1", isHeading: false, isMain: true, text: "3 ripe bananas"),
                Ingredient(id: "i2", isHeading: false, isMain: false, text: "2 cups flour"),
            ],
            preparationTimes: [
                PreparationTime(id: "p1", type: "Prep", timeString: "15 min"),
                PreparationTime(id: "p2", type: "Cook", timeString: "1 hr"),
            ],
            nutrition: {
                var n = NutritionInformation()
                n.servingSize = "1 slice"
                n.calories = 240
                n.protein = 9
                n.sodium = 300
                return n
            }()
        )
    }

    private func object(from data: Data) throws -> [String: Any] {
        try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // MARK: - Shape

    @Test func emitsCoreSchemaOrgFields() throws {
        let dict = try object(from: exporter.data(for: sampleRecipe()))

        #expect(dict["@context"] as? String == "https://schema.org")
        #expect(dict["@type"] as? String == "Recipe")
        #expect(dict["name"] as? String == "Banana Bread")
        #expect(dict["description"] as? String == "A moist, easy loaf.")
        #expect(dict["url"] as? String == "https://example.com/banana-bread")
        #expect(dict["recipeYield"] as? String == "1 loaf")

        let author = dict["author"] as? [String: Any]
        #expect(author?["@type"] as? String == "Person")
        #expect(author?["name"] as? String == "Jane Cook")

        #expect((dict["recipeIngredient"] as? [String]) == ["3 ripe bananas", "2 cups flour"])

        let steps = dict["recipeInstructions"] as? [[String: Any]]
        #expect(steps?.count == 2)
        #expect(steps?.first?["@type"] as? String == "HowToStep")
        #expect(steps?.first?["text"] as? String == "Mash the bananas.")
    }

    @Test func convertsDurationsToISO8601() throws {
        let dict = try object(from: exporter.data(for: sampleRecipe()))
        #expect(dict["prepTime"] as? String == "PT15M")
        #expect(dict["cookTime"] as? String == "PT1H")
    }

    @Test func emitsNutritionWithUnits() throws {
        let dict = try object(from: exporter.data(for: sampleRecipe()))
        let nutrition = try #require(dict["nutrition"] as? [String: Any])
        #expect(nutrition["@type"] as? String == "NutritionInformation")
        #expect(nutrition["servingSize"] as? String == "1 slice")
        #expect(nutrition["calories"] as? String == "240 calories")
        #expect(nutrition["proteinContent"] as? String == "9 g")
        #expect(nutrition["sodiumContent"] as? String == "300 mg")
    }

    @Test func omitsSectionHeadingsAndNonURLSourceDetails() throws {
        var recipe = sampleRecipe()
        recipe.sourceDetails = "Grandma's index card" // not a URL → no `url`
        recipe.ingredients = [
            Ingredient(id: "h1", isHeading: true, isMain: false, text: "For the topping"),
            Ingredient(id: "i1", isHeading: false, isMain: false, text: "1 cup sugar"),
        ]
        recipe.directions = [
            Direction(id: "h2", isHeading: true, text: "Topping"),
            Direction(id: "d1", isHeading: false, text: "Sprinkle on top."),
        ]
        let dict = try object(from: exporter.data(for: recipe))

        #expect(dict["url"] == nil)
        #expect((dict["recipeIngredient"] as? [String]) == ["1 cup sugar"])
        let steps = dict["recipeInstructions"] as? [[String: Any]]
        #expect(steps?.count == 1)
        #expect(steps?.first?["text"] as? String == "Sprinkle on top.")
    }

    @Test func includesLibraryMetadata() throws {
        let metadata = SchemaOrgRecipeJSONLDExporter.LibraryMetadata(
            courseName: "Dessert", categoryNames: ["Baking"], tagNames: ["weekend", "kid-friendly"]
        )
        let dict = try object(from: exporter.data(for: sampleRecipe(), metadata: metadata))
        #expect(dict["recipeCategory"] as? String == "Dessert")
        #expect(dict["keywords"] as? String == "weekend, kid-friendly, Baking")
    }

    @Test func multipleRecipesProduceAnArray() throws {
        let data = try exporter.data(for: [
            (recipe: sampleRecipe(), metadata: .init()),
            (recipe: sampleRecipe(), metadata: .init()),
        ])
        let array = try #require(try JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        #expect(array.count == 2)
        #expect(array.first?["@type"] as? String == "Recipe")
    }

    @Test func singleRecipeInArrayAPIProducesAnObject() throws {
        let data = try exporter.data(for: [(recipe: sampleRecipe(), metadata: .init())])
        let json = try JSONSerialization.jsonObject(with: data)
        // One recipe → a single object, not a one-element array.
        #expect(json is [String: Any])
        #expect(!(json is [Any]))
    }

    // MARK: - Round-trip through the importer

    @Test func roundTripsThroughImporter() throws {
        let data = try exporter.data(for: sampleRecipe())
        let json = try #require(String(data: data, encoding: .utf8))

        // The importer ingests JSON-LD embedded in an HTML <script> tag.
        let html = "<html><head><script type=\"application/ld+json\">\(json)</script></head><body></body></html>"
        let imported = SchemaOrgRecipeJSONLDImporter().parseRecipes(from: html)

        let recipe = try #require(imported.first)
        #expect(recipe.name == "Banana Bread")
        #expect(recipe.introduction == "A moist, easy loaf.")
        #expect(recipe.source == "Jane Cook")                       // author -> source
        #expect(recipe.sourceDetails == "https://example.com/banana-bread") // url -> sourceDetails
        #expect(recipe.ingredients.map(\.text) == ["3 ripe bananas", "2 cups flour"])
        #expect(recipe.directions.map(\.text) == ["Mash the bananas.", "Bake 60 minutes."])

        // Times: human -> ISO 8601 -> human.
        let prep = recipe.preparationTimes.first { $0.type == "Prep" }
        let cook = recipe.preparationTimes.first { $0.type == "Cook" }
        #expect(prep?.timeString == "15 min")
        #expect(cook?.timeString == "1 hr")

        // Nutrition values parse back to their numbers.
        #expect(recipe.nutrition?.calories == 240)
        #expect(recipe.nutrition?.protein == 9)
        #expect(recipe.nutrition?.sodium == 300)
        #expect(recipe.nutrition?.servingSize == "1 slice")
    }
}
