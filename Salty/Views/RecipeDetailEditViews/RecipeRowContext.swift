//
//  RecipeRowContext.swift
//  Salty
//
//  What `RecipeRowListEditor` hands each row it draws: where the row stands in the list, which row
//  has the keyboard, and the list operations a row's own controls trigger. The row decides what it
//  looks like; the editor owns the list, the focus, and the drag-and-drop.
//

import SwiftUI

/// Built and consumed inside view bodies, so it lives on the main actor like the views themselves
/// (its closures mutate view state and build a `ViewModifier`).
@MainActor
struct RecipeRowContext {
    /// The row's id, which is also the drag payload.
    let id: String
    /// Whether the row gets the tinted background of the striped-list effect.
    let isAlternateRow: Bool
    let canMoveUp: Bool
    let canMoveDown: Bool
    /// The list's measured width, so the drag preview can match it.
    let listWidth: CGFloat
    /// Which row's field has the keyboard. A row binds its first field with
    /// `.focused(context.focus, equals: context.id)` so a just-added row can be typed into at once.
    let focus: FocusState<String?>.Binding

    /// Inserts a blank row directly below this one.
    let addBelow: () -> Void
    let delete: () -> Void
    /// Each returns whether the row actually moved, so a key press on a row already at the end
    /// falls through rather than being silently eaten.
    let moveUp: () -> Bool
    let moveDown: () -> Bool

    /// ⌘⌥↑ / ⌘⌥↓ in a field moves the row. Each row applies this to every text field it holds:
    /// key presses are delivered to the focused field, and one on an enclosing view goes unheard
    /// (the system beeps instead), so it cannot be applied once to the whole row.
    var keyboardReordering: RecipeRowKeyboardReordering {
        RecipeRowKeyboardReordering(onMoveUp: moveUp, onMoveDown: moveDown)
    }
}
