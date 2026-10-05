//
//  RecipeRowDragHandle.swift
//  Salty
//
//  The grip at the end of an editable recipe row. Dragging it moves the row; its context menu and
//  its accessibility actions move the row up or down without a mouse, which the handle alone --
//  a static image that only reacted to drags -- never offered. (⌘⌥↑ / ⌘⌥↓ in the row's field does
//  the same; see RecipeRowKeyboardReordering.)
//
//  The drag payload is the row's id, so a drop can tell a real row from a stray text drag and never
//  acts on a stale index.
//

import SwiftUI

struct RecipeRowDragHandle: View {
    let context: RecipeRowContext
    /// What the preview that follows the cursor shows: the row's text, or `placeholder` while it is blank.
    let text: String
    let placeholder: String
    var stepNumber: Int? = nil
    var isHeading = false

    var body: some View {
        Label("Drag to Move", systemImage: "line.3.horizontal")
            .labelStyle(.iconOnly)
            .foregroundStyle(.tertiary)
            .help("Drag to move, or right-click to move up or down")
            .draggable(context.id) {
                RecipeRowDragPreview(
                    listWidth: context.listWidth,
                    stepNumber: stepNumber,
                    text: text,
                    placeholder: placeholder,
                    isHeading: isHeading
                )
            }
            .contextMenu {
                Button("Move Up", systemImage: "arrow.up") { _ = context.moveUp() }
                    .disabled(!context.canMoveUp)
                Button("Move Down", systemImage: "arrow.down") { _ = context.moveDown() }
                    .disabled(!context.canMoveDown)
                Divider()
                Button("Delete", systemImage: "minus.circle", role: .destructive, action: context.delete)
            }
            .accessibilityActions {
                if context.canMoveUp {
                    Button("Move Up") { _ = context.moveUp() }
                }
                if context.canMoveDown {
                    Button("Move Down") { _ = context.moveDown() }
                }
            }
    }
}
