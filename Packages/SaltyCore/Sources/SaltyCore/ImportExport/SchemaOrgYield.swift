//
//  SchemaOrgYield.swift
//  SaltyCore
//
//  Purpose: A recipe's yield, and how many it serves, from schema.org `recipeYield` values.
//  Rules: salty-contract SPEC.md WEB-023 (yield) and WEB-024 (servings, Salty's own rule).
//

import Foundation

struct SchemaOrgYield {

    /// One `recipeYield` value, read.
    struct Value {
        /// What the value says, as text: "4 to 6 servings", "10", "4 servings" for a QuantitativeValue.
        let text: String
        /// Whether it is just a number -- a count for machines, not a phrase for people.
        let isNumber: Bool
        /// A whole number that counts servings: a bare number, or a QuantitativeValue with no unit or a
        /// servings unit.
        let servingsCount: Int?
    }

    let values: [Value]

    /// The yield to show: of several values, the first that is not just a number, else the first number.
    /// Plugins publish `["4", "4 to 6 servings"]`, and the phrase is the one meant for people.
    var text: String {
        values.first(where: { !$0.isNumber })?.text ?? values.first?.text ?? ""
    }

    /// How many it serves (WEB-024), or nil when nothing says so. Not "the first number in the yield":
    /// "1 loaf" is not one serving, and `1 9" pie (8 servings)` serves eight.
    func servings(servingSize: String?) -> Int? {
        if let count = values.lazy.compactMap(\.servingsCount).first {
            return count
        }
        for value in values {
            if let count = Self.statedServings(in: value.text) {
                return count
            }
        }
        return servingSize.flatMap(Self.statedServings)
    }

    /// A count of servings or people stated in text: a number directly followed by servings, portions,
    /// people or persons, or directly after "serves"/"serving". The first number of a range.
    static func statedServings(in text: String) -> Int? {
        let range = #"(\d+)(?:\s*(?:-|\x{2013}|\x{2014}|to)\s*\d+)?"#
        let patterns = [
            range + #"\s*(?:servings?|portions?|people|persons?)\b"#,
            #"\b(?:serves|serving)\s*:?\s*"# + range,
        ]
        // The earliest statement in the text wins, whichever form it takes.
        let earliest = patterns.compactMap { pattern -> (location: Int, digits: Substring)? in
            guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
                  let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
                  let digits = Range(match.range(at: 1), in: text)
            else {
                return nil
            }
            return (match.range.location, text[digits])
        }.min { $0.location < $1.location }

        // A count too long to be a number is no count, not a wrapped one. 32 bits, as in SaltyKMP.
        guard let digits = earliest?.digits, let count = Int32(digits), count > 0 else { return nil }
        return Int(count)
    }

    /// Words that make a QuantitativeValue's unit a count of servings.
    static func isServingsUnit(_ unit: String) -> Bool {
        ["serving", "servings", "portion", "portions", "people", "person", "persons"]
            .contains(unit.trimmingCharacters(in: .whitespaces).lowercased())
    }
}
