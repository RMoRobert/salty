//
//  RecipeRowKeyboardReordering.swift
//  Salty
//
//  ⌘⌥↑ / ⌘⌥↓ on the row you are typing in moves it up or down, which is the one thing a List's
//  `onMove` would have given these editors for free. Reordering is otherwise mouse-only: the drag
//  handle is deliberately a small target, and nothing else can reach it from the keyboard.
//
//  ⌘⌥ rather than plain ⌥ because ⌥↑ and ⌥↓ are text-editing bindings -- the field would swallow
//  them before the row ever saw the key. ⌘↑ / ⌘↓ are taken too (start and end of the document).
//
//  Applied to the row's text field rather than to the list: key presses go to the focused view
//  first, so this is the one place guaranteed to see them.
//

import SwiftUI

struct RecipeRowKeyboardReordering: ViewModifier {
    /// Each returns whether the row actually moved; a row already at the end reports false and the
    /// key press falls through rather than being silently eaten.
    let onMoveUp: () -> Bool
    let onMoveDown: () -> Bool

    func body(content: Content) -> some View {
        content
            .onKeyPress(.upArrow, phases: .down) { keyPress in
                move(keyPress, using: onMoveUp)
            }
            .onKeyPress(.downArrow, phases: .down) { keyPress in
                move(keyPress, using: onMoveDown)
            }
    }

    private func move(_ keyPress: KeyPress, using action: () -> Bool) -> KeyPress.Result {
        guard keyPress.modifiers.contains(.command), keyPress.modifiers.contains(.option) else {
            return .ignored
        }
        return action() ? .handled : .ignored
    }
}
