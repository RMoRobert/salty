//
//  RecipeListEndDropZone.swift
//  Salty
//
//  The strip of space below the last row of the ingredient or direction editor.
//
//  Rows accept drops above themselves, which leaves the end of the list unreachable on its own -- so
//  this sits underneath them and takes the drop instead. The editors already drew an indicator for
//  this position, but nothing could ever target it.
//

import SwiftUI

struct RecipeListEndDropZone: View {
    let isActive: Bool
    /// Returns whether the drop was accepted.
    let onDrop: (String) -> Bool
    let onDropTargetChanged: (Bool) -> Void

    var body: some View {
        Color.clear
            .frame(maxWidth: .infinity, minHeight: 16)
            .overlay(alignment: .top) {
                RecipeListDropIndicator(isActive: isActive)
            }
            .contentShape(.rect)
            .dropDestination(for: String.self) { droppedIDs, _ in
                guard let droppedID = droppedIDs.first else { return false }
                return onDrop(droppedID)
            } isTargeted: { isTargeted in
                onDropTargetChanged(isTargeted)
            }
    }
}
