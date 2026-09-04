//
//  RecipeRowDropDestination.swift
//  Salty
//
//  Accepts a dragged row id, but only for rows that reorder themselves. When the container handles
//  reordering -- a List with `onMove` -- the destination has to be absent rather than merely
//  refusing, or it swallows the drop the List was going to act on.
//

import SwiftUI

struct RecipeRowDropDestination: ViewModifier {
    /// Returns whether the drop was accepted. Nil disables the destination entirely.
    let onDrop: ((String) -> Bool)?
    let onDropTargetChanged: ((Bool) -> Void)?

    func body(content: Content) -> some View {
        if let onDrop {
            content
                .dropDestination(for: String.self) { droppedIDs, _ in
                    guard let droppedID = droppedIDs.first else { return false }
                    return onDrop(droppedID)
                } isTargeted: { isTargeted in
                    onDropTargetChanged?(isTargeted)
                }
        } else {
            content
        }
    }
}
