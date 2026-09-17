//
//  StringWebLinksTests.swift
//  SaltyTests
//
//  `String.attributedWithWebLinks`, which lets the recipe detail view link the URL inside source
//  details such as "Adapted from https://example.com/recipe". The cases that matter are the ones
//  people write around a pasted address: a lead-in, a trailing full stop, brackets, quotes.
//

import Foundation
import Testing
import SaltyCore

@Suite struct StringWebLinksTests {

    /// The linked stretches of `text`, each paired with the URL it links to.
    private func links(in text: String) -> [String] {
        let attributed = text.attributedWithWebLinks
        return attributed.runs.compactMap { run in
            guard let url = run.link else { return nil }
            let linkedText = String(attributed[run.range].characters)
            #expect(url.absoluteString == linkedText)
            return linkedText
        }
    }

    @Test func linksAddressAfterLeadIn() {
        #expect(links(in: "Adapted from https://example.com/recipe") == ["https://example.com/recipe"])
        #expect(links(in: "Based on http://example.com/recipe2?id=4#notes") == ["http://example.com/recipe2?id=4#notes"])
    }

    @Test func keepsAllTextWhenLinking() {
        let text = "Adapted from https://example.com/recipe, with less sugar."
        #expect(String(text.attributedWithWebLinks.characters) == text)
    }

    @Test func leavesSentencePunctuationOutOfLink() {
        #expect(links(in: "Based on https://example.com/recipe.") == ["https://example.com/recipe"])
        #expect(links(in: "See https://example.com/a, then https://example.com/b!") == ["https://example.com/a", "https://example.com/b"])
    }

    @Test func leavesSurroundingBracketsAndQuotesOutOfLink() {
        #expect(links(in: "Bon Appétit (https://example.com/recipe)") == ["https://example.com/recipe"])
        #expect(links(in: "From “https://example.com/recipe”.") == ["https://example.com/recipe"])
        #expect(links(in: "From <https://example.com/recipe>") == ["https://example.com/recipe"])
    }

    @Test func keepsBracketsThatBelongToURL() {
        #expect(links(in: "(see https://en.wikipedia.org/wiki/Pie_(disambiguation))")
                == ["https://en.wikipedia.org/wiki/Pie_(disambiguation)"])
    }

    @Test func matchesSchemeCaseInsensitively() {
        #expect(links(in: "From HTTPS://example.com/recipe").count == 1)
    }

    @Test func leavesTextWithoutSchemeOrHostUnlinked() {
        #expect(links(in: "Grandma's recipe card").isEmpty)
        #expect(links(in: "Adapted from example.com/recipe").isEmpty)
        #expect(links(in: "Try https:// later").isEmpty)
        #expect(links(in: "").isEmpty)
    }
}
