//
//  RecipeHtmlTagsTests.swift
//  SaltyTests
//
//  Verifies the Tags section in HTML export (re-enabled now that tags live in a junction table and are
//  passed into asHtmlWithOptions).
//

import Testing
import Foundation
@testable import Salty
import SaltyCore

struct RecipeHtmlTagsTests {

    private func recipe() -> Recipe {
        Recipe(id: "r1", name: "Test Recipe")
    }

    // Note: the container id / `.recipe-tag` class appear in the stylesheet regardless, so assert on the
    // rendered `<h2>Tags</h2>` heading (">Tags<") and the tag text, which only exist when the section renders.

    @Test func includesTagsSectionWhenTagsProvided() {
        let html = recipe().asHtmlWithOptions(options: HTMLExportOptions(), tags: ["Weeknight", "Vegetarian"])
        #expect(html.contains(">Tags<"))
        #expect(html.contains("Weeknight"))
        #expect(html.contains("Vegetarian"))
    }

    @Test func omitsTagsSectionWhenNoTags() {
        let html = recipe().asHtmlWithOptions(options: HTMLExportOptions(), tags: [])
        #expect(!html.contains(">Tags<"))
    }

    @Test func includesCourseAndCategoriesWhenProvided() {
        let html = recipe().asHtmlWithOptions(options: HTMLExportOptions(), course: "Dessert", categories: ["Baking", "Holiday"])
        #expect(html.contains(">Course:<"))     // course label near the top (not the CSS)
        #expect(html.contains("Dessert"))
        #expect(html.contains(">Categories<"))  // categories section near the bottom
        #expect(html.contains("Baking"))
        #expect(html.contains("Holiday"))
    }

    @Test func omitsCourseAndCategoriesWhenEmpty() {
        let html = recipe().asHtmlWithOptions(options: HTMLExportOptions())
        #expect(!html.contains(">Course:<"))
        #expect(!html.contains(">Categories<"))
    }
}
