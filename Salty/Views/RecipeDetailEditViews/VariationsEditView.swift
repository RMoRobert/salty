//
//  VariationsEditView.swift
//  Salty
//
//  Created by Assistant on 1/27/25.
//

import SaltyCore
#if os(macOS)

import SwiftUI

struct VariationsEditView: View {
    @Binding var recipe: Recipe
    /// A row that was just added, for the list to scroll to and focus.
    @State private var newRowID: String?

    var showToolbar: Bool = true
    var showBottomButtons: Bool = false

    var body: some View {
        RecipeRowEditorShell(title: "Edit Variations", isStandalone: showToolbar, showsBottomButtons: showBottomButtons) {
            RecipeRowListEditor(
                items: $recipe.variations,
                newRowID: $newRowID,
                isStandalone: showToolbar,
                newRow: { .emptyRow() }
            ) { $variation, context in
                VariationEditRowView(variation: $variation, context: context)
            }
        } actions: {
            Button("New Variation", systemImage: "plus.circle") {
                withAnimation(.easeIn) {
                    newRowID = RecipeItemListEditor.append(.emptyRow(), to: &recipe.variations)
                }
            }
            .keyboardShortcut("n", modifiers: [.command])
        }
    }
}

// MARK: - Variation Edit Row View

struct VariationEditRowView: View {
    @Binding var variation: Variation
    let context: RecipeRowContext

    var body: some View {
        HStack {
            VStack {
                HStack {
                    // Icon
                    Image(systemName: "list.star")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    // Variation name field
                    TextField("Variation Name", text: $variation.variationName)
                        .textFieldStyle(.squareBorder)
                        .font(.headline)
                        .focused(context.focus, equals: variation.id)
                        .modifier(context.keyboardReordering)
                }
                HStack {
                    // Icon
                    Image(systemName: "list.star")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                        .opacity(0)
                    // Text field (multiline)
                    TextField("Text", text: $variation.text, axis: .vertical)
                        .textFieldStyle(.squareBorder)
                        .lineLimit(2...6)
                        .modifier(context.keyboardReordering)
                }
            }
            RecipeRowActionButtons(context: context, previewText: variation.variationName, placeholder: "Variation Name")
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
    }
}

#Preview {
    VariationsEditView(recipe: .constant(SampleData.sampleRecipes[0]))
}

#endif
