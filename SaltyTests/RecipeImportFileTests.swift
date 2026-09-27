//
//  RecipeImportFileTests.swift
//  SaltyTests
//
//  `RecipeImportFile`: MacGourmet and Crouton files read into `.saltyRecipe` exports and imported
//  through `SaltyRecipeImporter`. Format details are in CroutonImportTests.
//
//  Library rows are read back with raw SQL; see the note in RecipeWriterTests.
//

import Testing
import Foundation
import GRDB
import SaltyCore

struct RecipeImportFileTests {

    private static let jpegBytes = Data([0xFF, 0xD8, 0xFF, 0xE0, 1, 2, 3, 4])

    private func macGourmetFile(course: String = "Dessert") throws -> Data {
        let recipes: [[String: Any]] = [[
            "NAME": "Shortbread",
            "SUMMARY": "Three ingredients.",
            "CATEGORIES": [["NAME": "Cookies"], ["NAME": "Holiday"]],
            "COURSE_NAME": course,
            "DIRECTIONS_LIST": [["LABEL_TEXT": "Dough", "DIRECTION_TEXT": "Rub the butter into the flour."]],
            "INGREDIENTS": [["DESCRIPTION": "butter", "QUANTITY": "1", "MEASUREMENT": "cup"]],
            "IMAGE": Self.jpegBytes,
        ]]
        return try PropertyListSerialization.data(fromPropertyList: recipes, format: .xml, options: 0)
    }

    private func croutonFile(name: String = "Meat Pies") -> Data {
        let photo = Self.jpegBytes.base64EncodedString()
        return Data(#"""
            {"name": "\#(name)", "sourceName": "recipetineats.com", "serves": 16,
             "tags": ["Dinner", " Freezer "], "images": ["\#(photo)"],
             "steps": [{"order": 0, "step": "Sear the meat.", "isSection": false}],
             "ingredients": [{"order": 0, "ingredient": {"name": "salt"}}]}
            """#.utf8)
    }

    private func library() throws -> DatabaseQueue {
        let queue = try DatabaseQueue()
        try saltyMigrator().migrate(queue)
        try runSaltySharedMigrations(queue)
        return queue
    }

    // MARK: - Reading

    @Test func readsAMacGourmetFileWithItsCourseCategoriesAndPhoto() throws {
        let export = try #require(try RecipeImportFile.decode(macGourmetFile(), fileExtension: "mgourmet").first)

        #expect(export.name == "Shortbread")
        #expect(export.introduction == "Three ingredients.")
        #expect(export.course == "Dessert")
        #expect(export.categories == ["Cookies", "Holiday"])
        #expect(export.imageData == Self.jpegBytes)
        #expect(export.directions.map(\.text) == ["Dough", "Rub the butter into the flour."])
        #expect(export.directions.first?.isHeading == true)
        #expect(!export.ingredients.isEmpty)
    }

    @Test func macGourmetsNoCourseMarkerIsNoCourse() throws {
        #expect(try RecipeImportFile.decode(macGourmetFile(course: "--"), kind: .macGourmet).first?.course == nil)
    }

    @Test func readsACroutonFileWithItsTagsAndPhoto() throws {
        let export = try #require(try RecipeImportFile.decode(croutonFile(), fileExtension: ".crumb").first)

        #expect(export.name == "Meat Pies")
        #expect(export.source == "recipetineats.com")
        #expect(export.servings == 16)
        #expect(export.tags == ["Dinner", "Freezer"])
        #expect(export.imageData == Self.jpegBytes)
        #expect(export.directions.map(\.text) == ["Sear the meat."])
    }

    @Test func readsACroutonFileHoldingSeveralRecipes() throws {
        let file = Data("[".utf8) + croutonFile(name: "One") + Data(",".utf8) + croutonFile(name: "Two") + Data("]".utf8)
        #expect(try RecipeImportFile.decode(file, kind: .crouton).map(\.name) == ["One", "Two"])
    }

    @Test func readsASaltyRecipeFileByItsExtensionToo() throws {
        let file = Data(#"{"name": "Plain"}"#.utf8)
        #expect(try RecipeImportFile.decode(file, fileExtension: "saltyRecipe").map(\.name) == ["Plain"])
    }

    // MARK: - Refusing

    /// `.mgourmet4` carries its ingredients somewhere the importer doesn't read, and would import every
    /// recipe empty; see RecipeImportFileKind.
    @Test func refusesExtensionsItDoesNotImport() {
        #expect(throws: RecipeImportFileError.unsupportedFileType("mgourmet4")) {
            try RecipeImportFile.decode(Data(), fileExtension: "mgourmet4")
        }
        #expect(throws: RecipeImportFileError.unsupportedFileType("txt")) {
            try RecipeImportFile.decode(Data("x".utf8), fileExtension: ".txt")
        }
    }

    @Test func aFileThatIsNotItsFormatSaysSo() {
        #expect(throws: RecipeImportFileError.notA(.macGourmet)) {
            try RecipeImportFile.decode(Data("not a plist".utf8), kind: .macGourmet)
        }
        #expect(throws: RecipeImportFileError.notA(.crouton)) {
            try RecipeImportFile.decode(Data(#"{"hello": "world"}"#.utf8), kind: .crouton)
        }
        #expect(RecipeImportFileError.notA(.crouton).errorDescription == "This isn't a Crouton recipe file.")
    }

    // MARK: - Importing

    @Test func aMacGourmetRecipeImportsWithItsClassifiersMatchedByName() throws {
        let queue = try library()
        let export = try #require(try RecipeImportFile.decode(macGourmetFile(), kind: .macGourmet).first)

        let stored = try queue.write { db in try SaltyRecipeImporter.insert(export, in: db) }

        let categories = try queue.read { db in
            try String.fetchAll(db, sql: #"SELECT c."name" FROM "recipeCategory" rc JOIN "category" c ON c."id" = rc."categoryId" WHERE rc."recipeId" = ? ORDER BY c."name""#,
                                arguments: [stored.id])
        }
        #expect(categories.map { $0.lowercased() } == ["cookies", "holiday"])
        let course = try queue.read { db in
            try String.fetchOne(db, sql: #"SELECT c."name" FROM "recipe" r JOIN "course" c ON c."id" = r."courseId" WHERE r."id" = ?"#,
                                arguments: [stored.id])
        }
        #expect(course?.caseInsensitiveCompare("Dessert") == .orderedSame)
    }

    @Test func aCroutonRecipeImportsWithItsTags() throws {
        let queue = try library()
        let export = try #require(try RecipeImportFile.decode(croutonFile(), kind: .crouton).first)

        let stored = try queue.write { db in try SaltyRecipeImporter.insert(export, in: db) }

        let tags = try queue.read { db in
            try String.fetchAll(db, sql: #"SELECT t."name" FROM "recipeTag" rt JOIN "tag" t ON t."id" = rt."tagId" WHERE rt."recipeId" = ? ORDER BY t."name""#,
                                arguments: [stored.id])
        }
        #expect(tags == ["Dinner", "Freezer"])
    }
}
