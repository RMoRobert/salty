//
//  SchemaOrgRecipeJSONLDImporterImageURLTests.swift
//  SaltyTests
//
//  Covers extraction of the recipe photo URL (ScannedRecipe.imageURL) from the JSON-LD `image`
//  field in its common shapes (plain string, ImageObject, and arrays of either), plus the
//  parseRecipes compatibility wrapper. The importer is pure (no database / StructuredQueries),
//  so these are safe to run from the test bundle.
//

import Testing
import Foundation
@testable import Salty

struct SchemaOrgRecipeJSONLDImporterImageURLTests {

    private let importer = SchemaOrgRecipeJSONLDImporter()

    /// Serializes a JSON-LD object and wraps it in a minimal HTML page with a `ld+json` script tag,
    /// matching what the importer scrapes from a real recipe page.
    private func htmlPage(jsonLD object: [String: Any]) throws -> String {
        let data = try JSONSerialization.data(withJSONObject: object)
        let json = String(decoding: data, as: UTF8.self)
        return "<html><head><script type=\"application/ld+json\">\(json)</script></head><body></body></html>"
    }

    private func recipeObject(_ extra: [String: Any]) -> [String: Any] {
        var object: [String: Any] = ["@context": "https://schema.org", "@type": "Recipe", "name": "Test"]
        for (key, value) in extra { object[key] = value }
        return object
    }

    // MARK: - Image URL shapes

    @Test func extractsImageURLFromString() throws {
        let html = try htmlPage(jsonLD: recipeObject(["image": "https://example.com/photo.jpg"]))
        let scanned = try #require(importer.scanRecipes(from: html).first)
        #expect(scanned.imageURL == "https://example.com/photo.jpg")
    }

    @Test func extractsImageURLFromImageObject() throws {
        let imageObject: [String: Any] = ["@type": "ImageObject", "url": "https://example.com/photo.jpg"]
        let html = try htmlPage(jsonLD: recipeObject(["image": imageObject]))
        let scanned = try #require(importer.scanRecipes(from: html).first)
        #expect(scanned.imageURL == "https://example.com/photo.jpg")
    }

    @Test func extractsFirstImageURLFromArrayOfStrings() throws {
        let html = try htmlPage(jsonLD: recipeObject(["image": ["https://example.com/1.jpg", "https://example.com/2.jpg"]]))
        let scanned = try #require(importer.scanRecipes(from: html).first)
        #expect(scanned.imageURL == "https://example.com/1.jpg")
    }

    @Test func extractsFirstImageURLFromArrayOfImageObjects() throws {
        let imageObjects: [[String: Any]] = [
            ["@type": "ImageObject", "url": "https://example.com/1.jpg"],
            ["@type": "ImageObject", "url": "https://example.com/2.jpg"],
        ]
        let html = try htmlPage(jsonLD: recipeObject(["image": imageObjects]))
        let scanned = try #require(importer.scanRecipes(from: html).first)
        #expect(scanned.imageURL == "https://example.com/1.jpg")
    }

    @Test func imageURLIsNilWhenAbsent() throws {
        let html = try htmlPage(jsonLD: recipeObject([:]))
        let scanned = try #require(importer.scanRecipes(from: html).first)
        #expect(scanned.imageURL == nil)
    }

    // MARK: - Compatibility

    /// parseRecipes remains a thin wrapper over scanRecipes and must keep returning the same recipes.
    @Test func parseRecipesMatchesScanRecipes() throws {
        let html = try htmlPage(jsonLD: recipeObject(["image": "https://example.com/photo.jpg"]))
        let parsed = importer.parseRecipes(from: html)
        let scanned = importer.scanRecipes(from: html)
        #expect(parsed.count == 1)
        #expect(parsed.count == scanned.count)
        #expect(parsed.first?.name == scanned.first?.recipe.name)
    }
}
