//
//  RecipeExporterTests.swift
//  SaltyTests
//
//  The one export path behind every Export menu command: the same file shape and name rules for each
//  format, one recipe or several, with photos supplied by the app's closures.
//

import Testing
import Foundation
import GRDB
@testable import Salty
import SaltyCore

struct RecipeExporterTests {
    private let photo = Data("photo-bytes".utf8)

    private var exporter: RecipeExporter {
        let photo = photo
        return RecipeExporter(imageData: { _ in photo }, htmlImageBase64: { _ in "UEhPVE8=" })
    }

    private func library(_ names: [String]) throws -> (any DatabaseWriter, [Recipe]) {
        let queue = try makeSyncTestLibrary()
        let recipes = names.enumerated().map { index, name in
            Recipe(id: "r\(index)", name: name, lastModifiedDate: SyncTestClock.t1)
        }
        try queue.write { db in
            for recipe in recipes { try RecipeWriter.save(recipe, in: db, now: SyncTestClock.t1) }
        }
        return (queue, recipes)
    }

    @Test func oneRecipeIsABareSaltyObjectNamedAfterIt() throws {
        let (database, recipes) = try library(["Loaf"])
        let file = try exporter.export(recipes, as: .saltyFile, database: database)

        #expect(file.fileName == "Loaf.saltyRecipe")
        let json = try JSONSerialization.jsonObject(with: file.data)
        #expect(json is [String: Any], "one recipe is written as an object, as Salty shares it")
        let decoded = try SaltyRecipeFile.decode(file.data)
        #expect(decoded.map(\.name) == ["Loaf"])
        #expect(decoded.first?.imageData == photo)
    }

    @Test func severalRecipesAreAnArrayInTheGivenOrder() throws {
        let (database, recipes) = try library(["Rolls", "Loaf", "Bagels"])
        let file = try exporter.export(recipes, as: .saltyFile, database: database)

        #expect(file.fileName == "3_recipes.saltyRecipe")
        #expect(try JSONSerialization.jsonObject(with: file.data) is [Any])
        #expect(try SaltyRecipeFile.decode(file.data).map(\.name) == ["Rolls", "Loaf", "Bagels"])
    }

    @Test func jsonLDFollowsTheSameShapeAndNameRules() throws {
        let (database, recipes) = try library(["Loaf", "Rolls"])

        let one = try exporter.export([recipes[0]], as: .jsonLD, database: database)
        #expect(one.fileName == "Loaf.json")
        let object = try #require(try JSONSerialization.jsonObject(with: one.data) as? [String: Any])
        #expect(object["@type"] as? String == "Recipe")

        let two = try exporter.export(recipes, as: .jsonLD, database: database)
        #expect(two.fileName == "2_recipes.json")
        #expect((try JSONSerialization.jsonObject(with: two.data) as? [Any])?.count == 2)
    }

    @Test func htmlIsOneDocumentWithAMainPerRecipeAndThePhotoInlined() throws {
        let (database, recipes) = try library(["Loaf", "Rolls"])

        let one = try exporter.export([recipes[0]], as: .html(HTMLExportOptions()), database: database)
        let oneText = String(decoding: one.data, as: UTF8.self)
        #expect(one.fileName == "Loaf.html")
        #expect(oneText.contains("<title>Loaf</title>"))
        #expect(oneText.contains("UEhPVE8="))

        let two = try exporter.export(recipes, as: .html(HTMLExportOptions()), database: database)
        let twoText = String(decoding: two.data, as: UTF8.self)
        #expect(two.fileName == "2_recipes.html")
        #expect(twoText.contains("<title>2 Recipes</title>"))
        #expect(twoText.components(separatedBy: "<main").count - 1 == 2)
        #expect(twoText.components(separatedBy: "<style").count - 1 == 1, "one stylesheet for the whole document")
    }

    @Test func nothingToExportIsAnError() throws {
        let (database, _) = try library([])
        #expect(throws: RecipeExportError.nothingToExport) {
            try exporter.export([], as: .saltyFile, database: database)
        }
    }
}

/// Every read-only rendering numbers steps through `ChefStep`: headings and blank rows take no number.
struct DirectionNumberingAcrossOutputsTests {
    private let directions = [
        Direction(id: "1", text: "Mix"),
        Direction(id: "2", text: "   "),
        Direction(id: "3", isHeading: true, text: "Sauce"),
        Direction(id: "4", text: "Simmer"),
    ]

    @Test func theHtmlPageSkipsBlankRows() {
        let recipe = Recipe(id: "r", name: "Stew", directions: directions)
        let html = recipe.asHtmlWithOptions(options: HTMLExportOptions(), imageBase64: nil)
        #expect(html.contains(">1.<"))
        #expect(html.contains(">2.<"))
        #expect(!html.contains(">3.<"), "the blank row takes no number")
        #expect(html.components(separatedBy: "recipe-directions-step\"").count - 1 == 2)
    }

    @Test func thePlainTextExportSkipsBlankRows() throws {
        let export = try SaltyRecipeExport.fromRecipe(Recipe(id: "r", name: "Stew", directions: directions))
        let text = export.plainTextRepresentation
        #expect(text.contains("1. Mix\n\nSauce\n2. Simmer\n"))
        #expect(!text.contains("3."))
    }

    @Test func everyOutputAgreesWithChefView() {
        let numbers = ChefStep.steps(from: directions).compactMap(\.number)
        #expect(numbers == [1, 2])
    }
}
