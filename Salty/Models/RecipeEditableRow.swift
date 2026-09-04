//
//  RecipeEditableRow.swift
//  Salty
//
//  Ingredients and directions are edited the same way -- add a row, insert one below the row you are
//  on, delete, reorder by dragging -- and until now each editor carried its own copy of that logic.
//  This is the small surface RecipeItemListEditor needs to drive either list.
//

import Foundation
import SaltyCore
import UUIDV7

/// A row in one of the recipe's two body lists.
protocol RecipeEditableRow: Identifiable, Equatable, Sendable where ID == String {
    /// Headings are ordinary rows that format differently and are skipped when numbering steps.
    var isHeadingRow: Bool { get }

    /// A blank row with a fresh id, ready to be typed into.
    static func emptyRow(isHeading: Bool) -> Self
}

extension Ingredient: RecipeEditableRow {
    var isHeadingRow: Bool { isHeading }

    static func emptyRow(isHeading: Bool) -> Ingredient {
        emptyRow(isHeading: isHeading, isMain: false)
    }

    /// A row can be a heading or a main ingredient but never both -- `isMain` wins, matching what the
    /// toolbar's "New Main Ingredient" item does.
    static func emptyRow(isHeading: Bool, isMain: Bool) -> Ingredient {
        Ingredient(
            id: UUIDV7().uuidString,
            isHeading: isMain ? false : isHeading,
            isMain: isMain,
            text: ""
        )
    }
}

extension Direction: RecipeEditableRow {
    var isHeadingRow: Bool { isHeading ?? false }

    static func emptyRow(isHeading: Bool) -> Direction {
        Direction(id: UUIDV7().uuidString, isHeading: isHeading, text: "")
    }
}
