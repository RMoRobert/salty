//
//  ShoppingListFreeformConverter.swift
//  Salty
//
//  Created by Robert on 7/24/26.
//

import Foundation
import UUIDV7

/// Translates between the two shopping-list representations: freeform (Markdown-style) text and
/// structured checklist items. `text(from:)` backs the explicit "Convert to Freeform" action; the
/// inverse `items(from:)` is retained as its round-trip partner and for a possible future
/// freeform→checklist conversion. A list's kind is otherwise fixed at creation — neither direction
/// runs automatically.
public enum ShoppingListFreeformConverter {

    /// Serializes checklist items to freeform text using the same grammar `items(from:)` parses, so
    /// the two round-trip: headings become `# Heading`, items become `* [ ] text` / `* [x] text`.
    /// Item importance has no text form and is dropped.
    public static func text(from items: [ShoppingListListContents]) -> String {
        items.map { item in
            if item.isHeading ?? false {
                return "# \(item.text)"
            }
            let checkbox = (item.isCompleted ?? false) ? "[x]" : "[ ]"
            return "* \(checkbox) \(item.text)"
        }
        .joined(separator: "\n")
    }

    /// Parses freeform text into checklist items:
    /// - `#`/`##`-prefixed lines become heading rows (store/category sections)
    /// - `*`, `-`, `+`, or `•` bullets become items; a `[x]` checkbox marks the item completed
    /// - any other non-empty line becomes a plain item
    /// - blank lines are dropped
    public static func items(from text: String) -> [ShoppingListListContents] {
        var items: [ShoppingListListContents] = []
        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.isEmpty else { continue }

            if line.hasPrefix("#") {
                let title = line.drop(while: { $0 == "#" }).trimmingCharacters(in: .whitespaces)
                guard !title.isEmpty else { continue }
                items.append(ShoppingListListContents(
                    id: UUIDV7().uuidString, isHeading: true, text: title
                ))
                continue
            }

            var body = line
            if let first = body.first, "*-+•".contains(first) {
                body = body.dropFirst().trimmingCharacters(in: .whitespaces)
            }
            var isCompleted = false
            if body.hasPrefix("[") {
                if body.hasPrefix("[x]") || body.hasPrefix("[X]") {
                    isCompleted = true
                    body = body.dropFirst(3).trimmingCharacters(in: .whitespaces)
                } else if body.hasPrefix("[ ]") {
                    body = body.dropFirst(3).trimmingCharacters(in: .whitespaces)
                }
            }
            guard !body.isEmpty else { continue }
            items.append(ShoppingListListContents(
                id: UUIDV7().uuidString, isCompleted: isCompleted, text: body
            ))
        }
        return items
    }
}
