//
//  SchemaOrgRecipeJSONLDImporterHardeningTests.swift
//  SaltyTests
//
//  Covers the robustness limits the importer applies to untrusted web content (size caps, array caps,
//  HTML-entity decoding, and URL-scheme rejection). The importer is pure (no database / StructuredQueries),
//  so these are safe to run from the test bundle. See SchemaOrgRecipeJSONLDImporter.Limits.
//

import Testing
import Foundation
@testable import Salty
import SaltyCore

struct SchemaOrgRecipeJSONLDImporterHardeningTests {

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

    // MARK: - HTML entity decoding

    @Test func decodesSimpleHTMLEntities() throws {
        let html = try htmlPage(jsonLD: recipeObject(["name": "Salt &amp; Pepper &lt;Loaf&gt;"]))
        let recipe = try #require(importer.parseRecipes(from: html).first)
        #expect(recipe.name == "Salt & Pepper <Loaf>")
    }

    /// `&amp;` must be decoded LAST: an already-escaped `&amp;lt;` should resolve to the literal `&lt;`,
    /// not be double-decoded into `<`. This is the regression guard for the decode-ordering fix.
    @Test func doesNotDoubleDecodeEscapedEntities() throws {
        let html = try htmlPage(jsonLD: recipeObject(["name": "Tom &amp;lt; Jerry"]))
        let recipe = try #require(importer.parseRecipes(from: html).first)
        #expect(recipe.name == "Tom &lt; Jerry")
        #expect(!recipe.name.contains("<"))
    }

    /// Recipe plugins write a numeric character reference for every fraction they print, so a
    /// WordPress ingredient list is full of them. `&frac12;` and `&nbsp;` are just as common.
    @Test func decodesNumericAndNamedCharacterReferences() throws {
        let html = try htmlPage(jsonLD: recipeObject([
            "recipeIngredient": ["&#8531; cup oil", "&frac12; cup honey", "1&nbsp;egg", "&#x2154; cup flour"],
        ]))
        let recipe = try #require(importer.parseRecipes(from: html).first)
        #expect(recipe.ingredients.map(\.text) == ["\u{2153} cup oil", "\u{00BD} cup honey", "1 egg", "\u{2154} cup flour"])
    }

    /// A decoded `&nbsp;` is an ordinary space, and the trim happens after decoding — so a field that
    /// was nothing but a non-breaking space ends up empty rather than blank-looking. The KMP and .NET
    /// importers agree.
    @Test func decodedWhitespaceIsTrimmed() throws {
        let html = try htmlPage(jsonLD: recipeObject(["name": "&nbsp;Pancakes&nbsp;", "recipeYield": "&nbsp;"]))
        let recipe = try #require(importer.parseRecipes(from: html).first)
        #expect(recipe.name == "Pancakes")
        #expect(recipe.yield.isEmpty)
    }

    /// An ampersand that isn't a reference is just an ampersand, and must not eat what follows it.
    /// A trailing `;` is required, so "&notify" stays itself rather than decoding to "¬ify".
    @Test func leavesLoneAmpersandsAndUnknownReferencesAlone() throws {
        let html = try htmlPage(jsonLD: recipeObject(["name": "AT&T &notarealentity; &notify &amp; Sons"]))
        let recipe = try #require(importer.parseRecipes(from: html).first)
        #expect(recipe.name == "AT&T &notarealentity; &notify & Sons")
    }

    // MARK: - Durations

    /// A duration with nothing but seconds in it has no hours or minutes to render. Producing an
    /// empty label leaves a preparation time with no time in it; the original text is better.
    @Test func durationThatRendersToNothingKeepsItsText() throws {
        let html = try htmlPage(jsonLD: recipeObject(["cookTime": "PT45S"]))
        let recipe = try #require(importer.parseRecipes(from: html).first)
        #expect(recipe.preparationTimes.first?.timeString == "PT45S")
    }

    // MARK: - Size / count caps

    @Test func clampsOverlongStringFields() throws {
        let huge = String(repeating: "A", count: 30_000)
        let html = try htmlPage(jsonLD: recipeObject(["name": huge]))
        let recipe = try #require(importer.parseRecipes(from: html).first)
        #expect(recipe.name.count <= 20_000)
        #expect(recipe.name.count > 0)
    }

    @Test func capsIngredientAndDirectionArrays() throws {
        let ingredients = (0..<2_000).map { "ingredient \($0)" }
        let directions = (0..<2_000).map { ["@type": "HowToStep", "text": "step \($0)"] }
        let html = try htmlPage(jsonLD: recipeObject([
            "recipeIngredient": ingredients,
            "recipeInstructions": directions,
        ]))
        let recipe = try #require(importer.parseRecipes(from: html).first)
        #expect(recipe.ingredients.count <= 1_000)
        #expect(recipe.directions.count <= 1_000)
    }

    @Test func rejectsOversizedHTMLInput() {
        // Larger than Limits.maxInputBytes (8 MB): the importer should bail out before parsing.
        let oversized = String(repeating: "x", count: 8 * 1024 * 1024 + 16)
        #expect(importer.parseRecipes(from: oversized).isEmpty)
    }

    // MARK: - Source details

    /// AllRecipes, among others, publishes a Recipe with no `url` in it. The address is then the only
    /// record of where the recipe came from, which is what the field is for.
    @Test func sourceDetailsFallsBackToThePageAddress() throws {
        let html = try htmlPage(jsonLD: recipeObject([:]))
        let scanned = try #require(
            importer.scanRecipes(from: html, pageURL: "https://example.com/pancakes").first)
        #expect(scanned.recipe.sourceDetails == "https://example.com/pancakes")
    }

    @Test func sourceDetailsKeepsTheURLThePageDeclares() throws {
        let html = try htmlPage(jsonLD: recipeObject(["url": "https://example.com/canonical"]))
        let scanned = try #require(
            importer.scanRecipes(from: html, pageURL: "https://example.com/short").first)
        #expect(scanned.recipe.sourceDetails == "https://example.com/canonical")
    }

    /// The import browser opens on a bundled landing page. Recording that as a recipe's source would
    /// be worse than recording nothing.
    @Test func sourceDetailsIgnoresANonWebPageAddress() throws {
        let html = try htmlPage(jsonLD: recipeObject([:]))
        let scanned = try #require(
            importer.scanRecipes(from: html, pageURL: "file:///createRecipeFromWebLandingPage.html").first)
        #expect(scanned.recipe.sourceDetails.isEmpty)
    }

    // MARK: - URL scheme rejection (SSRF guard)

    @Test func refusesNonHTTPURLSchemes() async throws {
        let fileURL = try #require(URL(string: "file:///etc/passwd"))
        let recipes = await importer.parseRecipes(from: fileURL)
        #expect(recipes.isEmpty)
    }
}
