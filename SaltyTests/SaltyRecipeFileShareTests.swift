//
//  SaltyRecipeFileShareTests.swift
//  SaltyTests
//
//  Covers the file-based recipe share/open path used by AirDrop: encoding a recipe to a .saltyRecipe
//  file (as the Transferable's FileRepresentation does) and peeking its name(s) for the import
//  confirmation prompt. Pure JSON (no database / StructuredQueries), so safe in the test bundle.
//

import Testing
import Foundation
@testable import Salty
import SaltyCore

struct SaltyRecipeFileShareTests {

    private func export(_ name: String) throws -> SaltyRecipeExport {
        try SaltyRecipeExport.fromRecipe(Recipe(id: UUID().uuidString, name: name))
    }

    /// Writes `value` the same way the share FileRepresentation does (ISO-8601 dates) and returns the URL.
    private func writeTemp<T: Encodable>(_ value: T) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).saltyRecipe")
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        try encoder.encode(value).write(to: url)
        return url
    }

    @Test func peeksSingleRecipeName() throws {
        let url = try writeTemp(try export("Tomato Soup"))
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(SaltyRecipeImportHelper.peekRecipeNames(url) == ["Tomato Soup"])
    }

    @Test func peeksMultipleRecipeNames() throws {
        let url = try writeTemp([try export("Aioli"), try export("Brioche")])
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(SaltyRecipeImportHelper.peekRecipeNames(url) == ["Aioli", "Brioche"])
    }

    @Test func returnsEmptyForUndecodableFile() throws {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("\(UUID().uuidString).saltyRecipe")
        defer { try? FileManager.default.removeItem(at: url) }
        try Data("definitely not a recipe".utf8).write(to: url)
        #expect(SaltyRecipeImportHelper.peekRecipeNames(url).isEmpty)
    }
}
