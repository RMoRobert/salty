//
//  ShoppingListSummary.swift
//  Salty
//
//  Created by Robert on 7/26/26.
//

import Foundation

extension ShoppingList {
    /// One-line subtitle for a row in the lists column: how much is *in* the list, rather than how far
    /// through it you are. A checklist counts its items; a freeform list counts its non-blank lines.
    ///
    /// Heading rows are excluded from the checklist count — they group items, they aren't things to buy.
    /// Blank lines are excluded from the freeform count for the same reason: paragraph spacing in a
    /// Markdown document shouldn't inflate the total.
    var contentsSummary: String {
        if isFreeform {
            let lines = (contentsForFreeform ?? "")
                .split(separator: "\n", omittingEmptySubsequences: false)
                .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            return lines.isEmpty ? "Empty" : "\(lines.count) line\(lines.count == 1 ? "" : "s")"
        }
        let items = contentsForList.filter { !($0.isHeading ?? false) }
        return items.isEmpty ? "No items" : "\(items.count) item\(items.count == 1 ? "" : "s")"
    }
}
