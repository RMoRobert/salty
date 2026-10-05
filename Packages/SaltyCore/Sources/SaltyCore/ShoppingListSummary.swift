//
//  ShoppingListSummary.swift
//  Salty
//
//  Created by Robert on 7/26/26.
//

import Foundation

extension ShoppingList {
    /// How much is *in* a list, for its row subtitle. Each client words it.
    public enum ContentsCount: Equatable, Sendable {
        /// A freeform list's non-blank lines.
        case lines(Int)
        /// A checklist's items, headings excluded.
        case items(Int)
    }

    /// How much is *in* the list, rather than how far through it you are. A checklist counts its items;
    /// a freeform list counts its non-blank lines.
    ///
    /// Heading rows are excluded from the checklist count — they group items, they aren't things to buy.
    /// Blank lines are excluded from the freeform count for the same reason: paragraph spacing in a
    /// Markdown document shouldn't inflate the total.
    public var contentsCount: ContentsCount {
        if isFreeform {
            let lines = (contentsForFreeform ?? "")
                .split(separator: "\n", omittingEmptySubsequences: false)
                .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            return .lines(lines.count)
        }
        return .items(contentsForList.count { !($0.isHeading ?? false) })
    }
}
