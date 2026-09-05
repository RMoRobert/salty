//
//  RecipeEditableRow.swift
//  Salty
//
//  Ingredients, directions, notes, preparation times, and variations are all edited the same way --
//  add a row, insert one below the row you are on, delete, reorder -- and until now each editor
//  carried its own copy of that logic. This is the small surface RecipeItemListEditor needs to drive
//  any of them.
//
//  Only `emptyRow()` is a requirement: the reordering and deleting functions need nothing but a
//  stable id. Anything list-specific -- headings, main ingredients -- stays on the concrete type.
//

import Foundation
import SaltyCore
import UUIDV7

/// A row in one of the recipe's editable lists.
protocol RecipeEditableRow: Identifiable, Equatable, Sendable where ID == String {
    /// A blank row with a fresh id, ready to be typed into.
    static func emptyRow() -> Self
}

extension Ingredient: RecipeEditableRow {
    /// Headings format differently and are skipped when numbering steps.
    var isHeadingRow: Bool { isHeading }

    static func emptyRow() -> Ingredient {
        emptyRow(isHeading: false, isMain: false)
    }

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

    static func emptyRow() -> Direction {
        emptyRow(isHeading: false)
    }

    static func emptyRow(isHeading: Bool) -> Direction {
        Direction(id: UUIDV7().uuidString, isHeading: isHeading, text: "")
    }
}

extension Note: RecipeEditableRow {
    static func emptyRow() -> Note {
        Note(id: UUIDV7().uuidString, title: "", content: "")
    }
}

extension PreparationTime: RecipeEditableRow {
    static func emptyRow() -> PreparationTime {
        PreparationTime(id: UUIDV7().uuidString, type: "", timeString: "")
    }
}

extension Variation: RecipeEditableRow {
    static func emptyRow() -> Variation {
        Variation(id: UUIDV7().uuidString, variationName: "", text: "")
    }
}
