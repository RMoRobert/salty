//
//  RecipeHtmlDocument.swift
//  SaltyCore
//
//  One HTML document holding one or more recipes. A single recipe's `asHtmlWithOptions` is the
//  one-page case; multi-recipe HTML export and printing several selected recipes render all of them
//  into one document so the stylesheet is emitted once and each recipe becomes its own `<main>` —
//  which the print stylesheet starts on a fresh page (see `main + main` in RecipeToHtml's CSS).
//

import Foundation
import SwiftHtml

public enum RecipeHtmlDocument {
    /// Renders `pages` into a complete HTML document: shared `<head>` (stylesheet + theme), then one
    /// `<main>` per recipe in the given order.
    public static func render(_ pages: [RecipeHtmlPage], options: HTMLExportOptions,
                              theme: RecipeHtmlTheme = .modern, title: String) -> String {
        let doc = Document(.html) {
            Html {
                Head {
                    Title(title.htmlEscaped)
                    Meta().charset("utf-8")
                    Meta().name("viewport").content("width=device-width, initial-scale=1.0")
                    Style(getDefaultCSS() + "\n\n" + theme.overrideCSS)
                }
                Body {
                    for page in pages {
                        page.recipe.htmlMainElement(options: options, course: page.course,
                                                    categories: page.categories, tags: page.tags,
                                                    imageBase64: page.imageBase64)
                    }
                }
            }
        }
        return DocumentRenderer(minify: false, indent: 2).render(doc)
    }
}
