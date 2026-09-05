//
//  RecipeRowDragPreview.swift
//  Salty
//
//  Created by Robert 9/4/26
//
//  What follows the cursor while a ingredient, direction, note, etc. in recipe
//  editor is being dragged (default is the custom drag handle icon).
//

import SwiftUI

struct RecipeRowDragPreview: View {
    /// The width of the list the row was dragged out of, so the card reads as that row rather than as
    /// a floating label. Clamped below, since it arrives as 0 on the first layout pass.
    let listWidth: CGFloat
    /// Drawn ahead of the text (only used if is direction step)
    var stepNumber: Int? = nil
    let text: String
    /// In case user dragging blank/just-added row
    let placeholder: String
    var isHeading: Bool = false

    /// Wide enough to read a line of a direction but don't cover drop indicators
    private var width: CGFloat {
        min(max(listWidth - 32, 260), 480)
    }

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 8) {
            if let stepNumber {
                Text("\(stepNumber).")
                    .foregroundStyle(.secondary)
            }

            if text.isEmpty {
                Text(placeholder)
                    .foregroundStyle(.tertiary)
            } else {
                Text(text)
                    .bold(isHeading)
            }
        }
        .font(.callout)
        .lineLimit(2)
        .multilineTextAlignment(.leading)
        // A definite width, not a maximum: a drag preview is rendered against a zero-size proposal,
        // so my previous attempt with `maxWidth` left no room for text and just a square blob
        .frame(width: width, alignment: .leading)
        .fixedSize(horizontal: false, vertical: true)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.background)
                .shadow(color: .black.opacity(0.2), radius: 6, x: 2, y: 4)
        }
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(.separator)
        }
        .opacity(0.85)
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 16) {
        RecipeRowDragPreview(listWidth: 600, text: "2 cups all-purpose flour", placeholder: "Ingredient")
        RecipeRowDragPreview(listWidth: 600, text: "For the topping", placeholder: "Heading Title", isHeading: true)
        RecipeRowDragPreview(
            listWidth: 600,
            stepNumber: 3,
            text: "Place 1 Tbl oil in a large, heavy-based pot over medium high heat. Add half the meat and sear until lightly browned.",
            placeholder: "Direction text"
        )
        RecipeRowDragPreview(listWidth: 600, text: "", placeholder: "Ingredient")
    }
    .padding(40)
}
