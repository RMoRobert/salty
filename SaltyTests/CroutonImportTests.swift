//
//  CroutonImportTests.swift
//  SaltyTests
//
//  Covers the Crouton (.crumb) import: decoding Crouton's undocumented JSON, rebuilding its split
//  quantity/unit/name fields into Salty ingredient lines, and picking the real photo out of an image
//  array whose first entry is a thumbnail. Pure conversion (no database), so it runs in the test bundle.
//

import Testing
import Foundation
@testable import Salty
import SaltyCore

struct CroutonImportTests {

    private func decode(_ json: String) throws -> CroutonImportRecipe {
        try JSONDecoder().decode(CroutonImportRecipe.self, from: Data(json.utf8))
    }

    /// Converts and discards the inout side channels, for the cases that only assert on the recipe.
    private func convert(_ recipe: CroutonImportRecipe) -> Recipe {
        var imageData: Data?
        var tags: [String]?
        return recipe.convertToRecipe(imageData: &imageData, tags: &tags)
    }

    // MARK: - Whole-recipe conversion

    /// Mirrors the shape of a real export: ordered steps with a section heading, ordered ingredients
    /// with a SECTION divider and a quantity range, both duration fields, and free-text notes.
    private let fullRecipeJSON = """
    {
      "name": "Australian Mini Meat Pies",
      "uuid": "1097F242-952C-41BA-B7BF-70633183EE77",
      "rawDifficulty": "Easy",
      "rating": 0,
      "defaultScale": 1,
      "serves": 16,
      "duration": 30,
      "cookingDuration": 25,
      "isPublicRecipe": false,
      "sourceName": "recipetineats.com",
      "webLink": "http://www.recipetineats.com/party-pies-mini-beef-pies/",
      "notes": "Great food for parties that freezes extremely well!",
      "neutritionalInfo": "Calories: 331 Fat: 7.5g",
      "tags": ["Dinner", " Freezer "],
      "folderIDs": [],
      "images": [],
      "steps": [
        { "order": 1, "uuid": "B", "step": "Sear the meat.", "isSection": false },
        { "order": 0, "uuid": "A", "step": "Prepare filling", "isSection": true }
      ],
      "ingredients": [
        {
          "order": 1,
          "uuid": "I2",
          "quantity": { "quantityType": "POUND", "amount": 2, "secondaryAmount": 2.5 },
          "ingredient": { "name": "steak, cubed", "uuid": "N2" }
        },
        {
          "order": 0,
          "uuid": "I1",
          "quantity": { "quantityType": "SECTION" },
          "ingredient": { "name": "Filling", "uuid": "N1" }
        },
        {
          "order": 2,
          "uuid": "I3",
          "quantity": { "quantityType": "CUP", "amount": 0.5 },
          "ingredient": { "name": "beef stock", "uuid": "N3" }
        },
        {
          "order": 3,
          "uuid": "I4",
          "ingredient": { "name": "salt and pepper", "uuid": "N4" }
        }
      ]
    }
    """

    @Test func convertsTopLevelFields() throws {
        let recipe = convert(try decode(fullRecipeJSON))

        #expect(recipe.name == "Australian Mini Meat Pies")
        #expect(recipe.source == "recipetineats.com")
        #expect(recipe.sourceDetails == "http://www.recipetineats.com/party-pies-mini-beef-pies/")
        #expect(recipe.difficulty == .easy)
        #expect(recipe.rating == .notSet)
        #expect(recipe.servings == 16)
    }

    @Test func mapsDurationsToPrepAndCookTimes() throws {
        let recipe = convert(try decode(fullRecipeJSON))

        #expect(recipe.preparationTimes.count == 2)
        #expect(recipe.preparationTimes[0].type == "Prep")
        #expect(recipe.preparationTimes[0].timeString == "30 min")
        #expect(recipe.preparationTimes[1].type == "Cook")
        #expect(recipe.preparationTimes[1].timeString == "25 min")
    }

    @Test func sortsStepsByOrderAndKeepsSectionsAsHeadings() throws {
        let recipe = convert(try decode(fullRecipeJSON))

        #expect(recipe.directions.count == 2)
        #expect(recipe.directions[0].text == "Prepare filling")
        #expect(recipe.directions[0].isHeading == true)
        #expect(recipe.directions[1].text == "Sear the meat.")
        #expect(recipe.directions[1].isHeading == false)
    }

    @Test func rebuildsIngredientLinesFromSplitFields() throws {
        let recipe = convert(try decode(fullRecipeJSON))

        #expect(recipe.ingredients.count == 4)
        // SECTION carries no quantity and becomes a heading with just its name.
        #expect(recipe.ingredients[0].isHeading)
        #expect(recipe.ingredients[0].text == "Filling")
        // A secondaryAmount is a range; the unspaced hyphen is what Salty's scaler reads back.
        #expect(recipe.ingredients[1].text == "2-2 1/2 lb steak, cubed")
        #expect(recipe.ingredients[1].isHeading == false)
        // Decimal amounts become the fractions a cook would write, and the unit stays singular below one.
        #expect(recipe.ingredients[2].text == "1/2 cup beef stock")
        // No quantity object at all: the name stands alone.
        #expect(recipe.ingredients[3].text == "salt and pepper")
    }

    @Test func keepsNotesAndNutritionAsSeparateNotes() throws {
        let recipe = convert(try decode(fullRecipeJSON))

        #expect(recipe.notes.count == 2)
        #expect(recipe.notes[0].title == "Notes")
        #expect(recipe.notes[0].content == "Great food for parties that freezes extremely well!")
        // Crouton misspells the key as "neutritionalInfo"; the value is free text, so it stays verbatim.
        #expect(recipe.notes[1].title == "Nutrition")
        #expect(recipe.notes[1].content == "Calories: 331 Fat: 7.5g")
        // No usable nutrition values means the typed nutrition record stays empty.
        #expect(recipe.nutrition == nil)
    }

    @Test func returnsTrimmedTagsThroughSideChannel() throws {
        var imageData: Data?
        var tags: [String]?
        _ = try decode(fullRecipeJSON).convertToRecipe(imageData: &imageData, tags: &tags)

        #expect(tags == ["Dinner", "Freezer"])
        #expect(imageData == nil)
    }

    // MARK: - Sparse and malformed input

    @Test func importsRecipeWithOnlyAName() throws {
        let recipe = convert(try decode(#"{"name": "Toast"}"#))

        #expect(recipe.name == "Toast")
        #expect(recipe.difficulty == .notSet)
        #expect(recipe.servings == nil)
        #expect(recipe.preparationTimes.isEmpty)
        #expect(recipe.directions.isEmpty)
        #expect(recipe.ingredients.isEmpty)
        #expect(recipe.notes.isEmpty)
    }

    @Test func ignoresUnknownKeys() throws {
        let recipe = convert(try decode(#"{"name": "Toast", "someFutureCroutonField": {"a": 1}}"#))
        #expect(recipe.name == "Toast")
    }

    @Test func dropsEmptyStepsAndUnnamedIngredients() throws {
        let json = """
        {
          "name": "Sparse",
          "steps": [{ "step": "   " }, { "step": "Real step" }],
          "ingredients": [
            { "quantity": { "quantityType": "CUP", "amount": 1 }, "ingredient": { "name": "" } },
            { "ingredient": { "name": "flour" } }
          ]
        }
        """
        let recipe = convert(try decode(json))

        #expect(recipe.directions.map(\.text) == ["Real step"])
        #expect(recipe.ingredients.map(\.text) == ["flour"])
    }

    @Test func fallsBackToFileOrderWhenOrderIsMissing() throws {
        let json = """
        {
          "name": "Unordered",
          "steps": [{ "step": "first" }, { "step": "second" }, { "step": "third" }]
        }
        """
        let recipe = convert(try decode(json))
        #expect(recipe.directions.map(\.text) == ["first", "second", "third"])
    }

    @Test(arguments: [("Easy", Difficulty.easy), ("medium", .medium), ("Hard", .difficult), ("Wat", .notSet)])
    func mapsDifficulty(raw: String, expected: Difficulty) throws {
        let recipe = convert(try decode(#"{"name": "D", "rawDifficulty": "\#(raw)"}"#))
        #expect(recipe.difficulty == expected)
    }

    @Test func formatsDurationsOverAnHour() throws {
        let recipe = convert(try decode(#"{"name": "Slow", "duration": 90, "cookingDuration": 120}"#))
        #expect(recipe.preparationTimes.map(\.timeString) == ["1 hr 30 min", "2 hr"])
    }

    @Test func skipsZeroDurations() throws {
        let recipe = convert(try decode(#"{"name": "Quick", "duration": 0, "cookingDuration": 5}"#))
        #expect(recipe.preparationTimes.map(\.type) == ["Cook"])
    }

    // MARK: - Images

    /// Crouton writes a 280x280 thumbnail first and the full-size photo second, so the import has to
    /// take the largest payload rather than the first one.
    @Test func picksLargestImageRatherThanFirst() throws {
        let thumbnail = Data("small".utf8)
        let photo = Data("a much larger payload".utf8)
        let json = """
        {"name": "Photographed", "images": ["\(thumbnail.base64EncodedString())", "\(photo.base64EncodedString())"]}
        """

        var imageData: Data?
        var tags: [String]?
        _ = try decode(json).convertToRecipe(imageData: &imageData, tags: &tags)

        #expect(imageData == photo)
    }

    @Test func skipsMalformedBase64WithoutFailingTheRecipe() throws {
        let photo = Data("real photo bytes".utf8)
        let json = """
        {"name": "Photographed", "images": ["!!!not base64!!!", "\(photo.base64EncodedString())"]}
        """

        var imageData: Data?
        var tags: [String]?
        let recipe = try decode(json).convertToRecipe(imageData: &imageData, tags: &tags)

        #expect(recipe.name == "Photographed")
        #expect(imageData == photo)
    }

    /// `sourceImage` is a 16-48px favicon of the source site, never a recipe photo, so it's ignored.
    @Test func ignoresSourceImage() throws {
        let favicon = Data("favicon bytes that are longer than nothing".utf8)
        let json = """
        {"name": "No photo", "images": [], "sourceImage": "\(favicon.base64EncodedString())"}
        """

        var imageData: Data?
        var tags: [String]?
        _ = try decode(json).convertToRecipe(imageData: &imageData, tags: &tags)

        #expect(imageData == nil)
    }

    // MARK: - Quantity types

    @Test func abbreviatesMeasurementUnits() {
        #expect(CroutonQuantityType.unitText(forRawType: "TEASPOON", amount: 2) == "tsp")
        #expect(CroutonQuantityType.unitText(forRawType: "TABLESPOON", amount: 2) == "Tbsp")
        #expect(CroutonQuantityType.unitText(forRawType: "GRAMS", amount: 200) == "g")
        #expect(CroutonQuantityType.unitText(forRawType: "POUND", amount: 2) == "lb")
        #expect(CroutonQuantityType.unitText(forRawType: "OUNCE", amount: 8) == "oz")
    }

    @Test func pluralizesSpelledOutUnits() {
        #expect(CroutonQuantityType.unitText(forRawType: "CUP", amount: 0.5) == "cup")
        #expect(CroutonQuantityType.unitText(forRawType: "CUP", amount: 1) == "cup")
        #expect(CroutonQuantityType.unitText(forRawType: "CUP", amount: 3) == "cups")
        #expect(CroutonQuantityType.unitText(forRawType: "PINCH", amount: 2) == "pinches")
        #expect(CroutonQuantityType.unitText(forRawType: "BUNCH", amount: 2) == "bunches")
        #expect(CroutonQuantityType.unitText(forRawType: "CAN", amount: 1) == "can")
        #expect(CroutonQuantityType.unitText(forRawType: "CUP", amount: nil) == "cup")
    }

    @Test func writesNoUnitForCountsAndSections() {
        #expect(CroutonQuantityType.unitText(forRawType: "ITEM", amount: 3) == "")
        #expect(CroutonQuantityType.unitText(forRawType: "SECTION", amount: nil) == "")
        #expect(CroutonQuantityType.unitText(forRawType: "", amount: 1) == "")
    }

    /// Crouton's unit list isn't documented, so an unrecognized token has to degrade to something
    /// readable instead of being dropped.
    @Test func fallsBackToTheRawTokenForUnknownUnits() {
        #expect(CroutonQuantityType.unitText(forRawType: "FLUID_DRAM", amount: 2) == "fluid dram")
    }

    @Test func detectsSectionTokenCaseInsensitively() {
        #expect(CroutonQuantityType.isSection(rawType: "SECTION"))
        #expect(CroutonQuantityType.isSection(rawType: " section "))
        #expect(!CroutonQuantityType.isSection(rawType: "CUP"))
        #expect(!CroutonQuantityType.isSection(rawType: nil))
    }

    // MARK: - File type detection

    @Test func detectsImportableFileKinds() {
        #expect(RecipeImportFileKind(fileExtension: "crumb") == .crouton)
        #expect(RecipeImportFileKind(fileExtension: "CRUMB") == .crouton)
        #expect(RecipeImportFileKind(fileExtension: "saltyRecipe") == .saltyRecipe)
        #expect(RecipeImportFileKind(fileExtension: "mgourmet") == .macGourmet)
        // .mgourmet4 is a different plist schema that decodes into ingredient-less recipes, so it must
        // NOT be claimed as importable. See the note in RecipeImportFileKind.
        #expect(RecipeImportFileKind(fileExtension: "mgourmet4") == nil)
        #expect(RecipeImportFileKind(fileExtension: "mgourmet3") == nil)
        #expect(RecipeImportFileKind(fileExtension: "txt") == nil)
        #expect(RecipeImportFileKind(url: URL(filePath: "/tmp/Basil Pesto.crumb")) == .crouton)
    }

    // MARK: - Import summary

    @Test func summarizesRecipeAndFileCounts() {
        #expect(ImportRecipesFromFileView.summaryMessage(recipeCount: 1, fileCount: 1, failedFileNames: [])
            == "Imported 1 recipe from 1 file.")
        #expect(ImportRecipesFromFileView.summaryMessage(recipeCount: 80, fileCount: 80, failedFileNames: [])
            == "Imported 80 recipes from 80 files.")
    }

    @Test func summaryNamesFailedFilesAndTruncatesLongLists() {
        let one = ImportRecipesFromFileView.summaryMessage(recipeCount: 2, fileCount: 3, failedFileNames: ["bad.crumb"])
        #expect(one.contains("Could not read 1 file: bad.crumb"))

        let many = ImportRecipesFromFileView.summaryMessage(
            recipeCount: 2,
            fileCount: 9,
            failedFileNames: (1...7).map { "f\($0).crumb" }
        )
        #expect(many.contains("Could not read 7 files:"))
        #expect(many.contains("f5.crumb"))
        #expect(!many.contains("f6.crumb"))
        #expect(many.contains("and 2 more"))
    }
}
