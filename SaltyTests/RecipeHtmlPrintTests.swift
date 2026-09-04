//
//  RecipeHtmlPrintTests.swift
//  SaltyTests
//
//  Guards the print layout invariants in the recipe stylesheet and the combined (multi-recipe) document.
//  The layout rules were established by paginating the real stylesheet through WKWebView's print path
//  on macOS: a grid/flex ancestor above the lists makes WebKit slice text lines across pages, so the
//  print stylesheet must flatten `main` to block flow. These tests keep that from regressing silently.
//

import Testing
import Foundation
@testable import Salty
import SaltyCore

struct RecipeHtmlPrintTests {

    private func recipe(_ id: String, name: String) -> Recipe {
        var recipe = Recipe(id: id, name: name)
        recipe.ingredients = [Ingredient(id: "i1", text: "1 cup flour")]
        recipe.directions = [Direction(id: "d1", text: "Mix.")]
        return recipe
    }

    /// The `@media print { ... }` block of the base stylesheet.
    private func printCSS() -> String {
        let css = getDefaultCSS()
        guard let range = css.range(of: "@media print {") else { return "" }
        return String(css[range.lowerBound...])
    }

    private func rule(_ selector: String, in css: String) -> String {
        guard let start = css.range(of: selector + " {") ?? css.range(of: selector + "{"),
              let end = css[start.upperBound...].range(of: "}") else { return "" }
        return String(css[start.upperBound..<end.lowerBound])
    }

    @Test func printFlattensMainToBlockFlow() {
        let css = printCSS()
        let main = rule("\n    main", in: css)
        #expect(main.contains("display: block !important"))
        #expect(!css.contains("grid-template-columns"))
    }

    @Test func printKeepsListItemsAndHeadingsTogether() {
        let css = printCSS()
        #expect(rule(".recipe-directions-list li", in: css).contains("break-inside: avoid"))
        #expect(rule(".recipe-ingredients-list li", in: css).contains("break-inside: avoid"))
        #expect(rule("""
            .recipe-ingredient-heading,
            .recipe-directions-heading,
            .recipe-note-heading,
            .recipe-variation-heading
        """.replacing("        ", with: "    "), in: css).contains("break-after: avoid"))
    }

    @Test func printFlattensChipRows() {
        let css = printCSS()
        let chips = rule("""
            #recipe-prep-time-list,
            #categories-list,
            #tags-list
        """.replacing("        ", with: "    "), in: css)
        #expect(chips.contains("display: block !important"))
    }

    @Test func printLetsParagraphsBreakBetweenLines() {
        let css = printCSS()
        let paragraphs = rule("p, .recipe-introduction, .recipe-note-text, .recipe-variation-text", in: css)
        #expect(paragraphs.contains("break-inside: auto"))
        #expect(paragraphs.contains("orphans: 3"))
        #expect(paragraphs.contains("widows: 3"))
    }

    @Test func combinedDocumentHasOneMainPerRecipeAndOneStylesheet() {
        let pages = [
            RecipeHtmlPage(recipe: recipe("a", name: "Alpha"), imageBase64: nil),
            RecipeHtmlPage(recipe: recipe("b", name: "Beta"), imageBase64: nil),
        ]
        let html = RecipeHtmlDocument.render(pages, options: HTMLExportOptions(), title: "2 Recipes")
        #expect(html.components(separatedBy: "<style>").count - 1 == 1)
        #expect(html.components(separatedBy: "<html>").count - 1 == 1)
        // Count elements in the body only, so nothing in the stylesheet can skew it.
        let body = html[html.range(of: "</style>")!.upperBound...]
        #expect(body.components(separatedBy: "<main>").count - 1 == 2)
        #expect(html.contains("<title>2 Recipes</title>"))
        #expect(html.contains(">Alpha<"))
        #expect(html.contains(">Beta<"))
        // Alpha renders before Beta.
        #expect(html.range(of: ">Alpha<")!.lowerBound < html.range(of: ">Beta<")!.lowerBound)
    }

    @Test func combinedDocumentStartsEachFurtherRecipeOnANewPage() {
        #expect(rule("\n    main + main", in: printCSS()).contains("break-before: page"))
    }

    @Test func singleRecipeDocumentIsTheOnePageCase() {
        let single = recipe("a", name: "Alpha").asHtmlWithOptions(options: HTMLExportOptions(), imageBase64: nil)
        let combined = RecipeHtmlDocument.render([RecipeHtmlPage(recipe: recipe("a", name: "Alpha"), imageBase64: nil)],
                                                 options: HTMLExportOptions(), title: "Alpha")
        #expect(single == combined)
    }
}
