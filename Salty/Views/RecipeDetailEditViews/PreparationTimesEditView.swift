//
//  PreparationTimesEditView.swift
//  Salty
//
//  Created by Assistant on 1/27/25.
//

import SaltyCore
#if os(macOS)

import SwiftUI

struct PreparationTimesEditView: View {
    @Binding var recipe: Recipe
    /// A row that was just added, for the list to scroll to and focus.
    @State private var newRowID: String?

    var showToolbar: Bool = true
    var showBottomButtons: Bool = false

    var body: some View {
        RecipeRowEditorShell(title: "Edit Preparation Times", isStandalone: showToolbar, showsBottomButtons: showBottomButtons) {
            RecipeRowListEditor(
                items: $recipe.preparationTimes,
                newRowID: $newRowID,
                isStandalone: showToolbar,
                newRow: { .emptyRow() }
            ) { $preparationTime, context in
                PreparationTimeEditRowView(preparationTime: $preparationTime, context: context)
            }
        } actions: {
            Button("New Time", systemImage: "plus.circle") {
                withAnimation(.easeIn) {
                    newRowID = RecipeItemListEditor.append(.emptyRow(), to: &recipe.preparationTimes)
                }
            }
            .keyboardShortcut("n", modifiers: [.command])
        }
    }
}

// MARK: - Preparation Time Edit Row View

struct PreparationTimeEditRowView: View {
    @Binding var preparationTime: PreparationTime
    let context: RecipeRowContext

    /// The two fields read as one line while dragging: "Bake -- 1 hr, 30 min".
    private var previewText: String {
        [preparationTime.type, preparationTime.timeString]
            .filter { !$0.isEmpty }
            .joined(separator: " -- ")
    }

    var body: some View {
        HStack {
            TextField("Type (e.g., \"Bake\")", text: $preparationTime.type)
                .textFieldStyle(.squareBorder)
                .focused(context.focus, equals: preparationTime.id)
                .modifier(context.keyboardReordering)
                .frame(maxWidth: .infinity)

            TextField("Time (e.g., \"1 hr, 30 min\")", text: $preparationTime.timeString)
                .textFieldStyle(.squareBorder)
                .modifier(context.keyboardReordering)
                .frame(maxWidth: .infinity)

            RecipeRowActionButtons(context: context, previewText: previewText, placeholder: "New Time")
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 3)
    }
}

#Preview {
    PreparationTimesEditView(recipe: .constant(SampleData.sampleRecipes[0]))
}

#endif
