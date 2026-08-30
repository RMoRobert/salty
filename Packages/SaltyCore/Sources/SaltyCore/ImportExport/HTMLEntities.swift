//
//  HTMLEntities.swift
//  SaltyCore
//
//  Purpose: Turn the HTML character references that survive into scraped text back into the characters
//  they stand for. Shared by the JSON-LD importer and by the web import screen's manual field capture,
//  so the same page produces the same text however it was lifted off it.
//

import Foundation
import SwiftSoup

/// Decodes HTML character references in text taken off a web page.
public enum HTMLEntities {

    /// Decodes `text` in a single pass.
    ///
    /// One pass is what makes an already-escaped `&amp;lt;` resolve to the literal `&lt;` rather than
    /// being decoded twice into `<`. A hand-rolled chain of `replacingOccurrences` gets the same answer
    /// for a handful of named entities if `&amp;` is done last — which is what this replaced — but it
    /// can only ever handle the entities somebody thought to list. Recipe plugins write a numeric
    /// reference for every fraction they print, so a WordPress ingredient list arrives full of
    /// `&#8531;` and `&frac12;`, and those were reaching the editor undecoded.
    ///
    /// Strict, so a trailing `;` is required. HTML's legacy entities are recognisable without one, and
    /// under that rule "&notify" decodes to "¬ify" — not a trade worth making for text that always
    /// arrives properly terminated.
    ///
    /// A decoded `&nbsp;` becomes an ordinary space rather than U+00A0: an invisible character that a
    /// search for "1 cup" would not match is not what the page meant to say.
    public static func decode(_ text: String) -> String {
        // Unescaping can only fail on input the parser can't walk at all; the honest answer to that is
        // the text as it arrived, not an empty field.
        guard let decoded = try? Entities.unescape(string: text, strict: true) else {
            return text
        }

        return decoded.replacingOccurrences(of: "\u{00A0}", with: " ")
    }
}
