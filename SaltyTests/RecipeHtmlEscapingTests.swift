//
//  RecipeHtmlEscapingTests.swift
//  SaltyTests
//
//  Recipe text can come from untrusted sources (web import, shared .saltyRecipe files, the sync
//  server) and SwiftHtml renders text nodes verbatim, so every user-editable field must be
//  HTML-escaped before it reaches the recipe document. These tests pin that behavior: markup in
//  any field must come out entity-encoded, never as live tags.
//

import Testing
import Foundation
@testable import Salty

struct RecipeHtmlEscapingTests {

    private let payload = "<script>alert(1)</script>"
    private let escapedPayload = "&lt;script&gt;alert(1)&lt;/script&gt;"

    @Test func escapesCoreTextFields() {
        var recipe = Recipe(id: "r1", name: "Name \(payload)")
        recipe.source = "Source \(payload)"
        recipe.sourceDetails = "Details \(payload)"
        recipe.introduction = "Intro \(payload)"
        recipe.yield = "Yield \(payload)"

        let html = recipe.asHtmlWithOptions(options: HTMLExportOptions())

        #expect(!html.contains(payload))
        #expect(html.contains("Name \(escapedPayload)"))
        #expect(html.contains("Source \(escapedPayload)"))
        #expect(html.contains("Details \(escapedPayload)"))
        #expect(html.contains("Intro \(escapedPayload)"))
        #expect(html.contains("Yield \(escapedPayload)"))
    }

    @Test func escapesIngredientsDirectionsNotesAndVariations() {
        var recipe = Recipe(id: "r1", name: "Test")
        recipe.ingredients = [
            Ingredient(id: "i1", isHeading: true, isMain: false, text: "Heading \(payload)"),
            Ingredient(id: "i2", isHeading: false, isMain: false, text: "Item \(payload)"),
        ]
        recipe.directions = [
            Direction(id: "d1", isHeading: true, text: "Section \(payload)"),
            Direction(id: "d2", isHeading: false, text: "Step \(payload)"),
        ]
        recipe.notes = [Note(id: "n1", title: "NoteTitle \(payload)", content: "NoteBody \(payload)")]
        recipe.variations = [Variation(id: "v1", variationName: "VarName \(payload)", text: "VarBody \(payload)")]
        recipe.preparationTimes = [PreparationTime(id: "p1", type: "Prep \(payload)", timeString: "Time \(payload)")]

        let html = recipe.asHtmlWithOptions(options: HTMLExportOptions())

        #expect(!html.contains(payload))
        for prefix in ["Heading", "Item", "Section", "Step", "NoteTitle", "NoteBody", "VarName", "VarBody", "Prep", "Time"] {
            #expect(html.contains("\(prefix) \(escapedPayload)"), "expected escaped \(prefix) field")
        }
    }

    @Test func escapesCourseCategoriesAndTags() {
        let recipe = Recipe(id: "r1", name: "Test")
        let html = recipe.asHtmlWithOptions(
            options: HTMLExportOptions(),
            course: "Course \(payload)",
            categories: ["Cat \(payload)"],
            tags: ["Tag \(payload)"]
        )

        #expect(!html.contains(payload))
        #expect(html.contains("Course \(escapedPayload)"))
        #expect(html.contains("Cat \(escapedPayload)"))
        #expect(html.contains("Tag \(escapedPayload)"))
    }

    @Test func escapesAllSignificantCharactersAndLeavesPlainTextAlone() {
        #expect(#"&<>"'"#.htmlEscaped == "&amp;&lt;&gt;&quot;&#39;")
        // `&` is escaped first, so an existing entity is not double-escaped into a live one.
        #expect("&amp;".htmlEscaped == "&amp;amp;")
        #expect("Sauté 2 cups, stir & serve — no markup".htmlEscaped == "Sauté 2 cups, stir &amp; serve — no markup")
    }

    @Test func attackPayloadInImgTagNeverRendersAsElement() {
        var recipe = Recipe(id: "r1", name: "Test")
        recipe.ingredients = [Ingredient(id: "i1", isHeading: false, isMain: false, text: #"<img src=x onerror="fetch('https://evil.example')">"#)]

        let html = recipe.asHtmlWithOptions(options: HTMLExportOptions())

        #expect(!html.contains("<img"))
        #expect(html.contains("&lt;img src=x onerror=&quot;"))
    }
}
