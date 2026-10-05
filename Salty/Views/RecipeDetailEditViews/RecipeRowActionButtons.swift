//
//  RecipeRowActionButtons.swift
//  Salty
//
//  The add, delete and drag controls every editable recipe row carries. Four of the five row kinds
//  show them as one trailing group (`RecipeRowActionButtons`); the ingredient row lays the same
//  pieces out in its own fixed columns.
//

import SwiftUI

/// The green "+" that inserts a blank row below this one.
struct RecipeRowAddButton: View {
    let context: RecipeRowContext

    var body: some View {
        Button("Add", systemImage: "plus.circle.fill", action: context.addBelow)
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
            .foregroundStyle(Color.green)
    }
}

/// The red "−" that removes this row.
struct RecipeRowDeleteButton: View {
    let context: RecipeRowContext

    var body: some View {
        Button("Delete", systemImage: "minus.circle.fill", action: context.delete)
            .labelStyle(.iconOnly)
            .buttonStyle(.plain)
            .foregroundStyle(.red)
    }
}

/// Add, delete and the drag handle in a row, as the direction, note, variation and preparation-time
/// rows show them.
struct RecipeRowActionButtons: View {
    let context: RecipeRowContext
    /// What the drag preview shows; see `RecipeRowDragHandle`.
    let previewText: String
    let placeholder: String
    var stepNumber: Int? = nil
    var isHeading = false

    var body: some View {
        HStack(spacing: 4) {
            RecipeRowAddButton(context: context)
            RecipeRowDeleteButton(context: context)
            RecipeRowDragHandle(
                context: context,
                text: previewText,
                placeholder: placeholder,
                stepNumber: stepNumber,
                isHeading: isHeading
            )
        }
    }
}
