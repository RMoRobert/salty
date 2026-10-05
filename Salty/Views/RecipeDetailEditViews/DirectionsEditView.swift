//
//  DirectionsEditView.swift
//  Salty
//
//  Created by Robert on 5/29/23.
//

import SaltyCore
#if os(macOS)

import SwiftUI

struct DirectionsEditView: View {
    @Binding var recipe: Recipe
    /// A row that was just added, for the list to scroll to and focus.
    @State private var newRowID: String?

    var showToolbar: Bool = true
    var showBottomButtons: Bool = false

    var body: some View {
        RecipeRowEditorShell(title: "Edit Directions", isStandalone: showToolbar, showsBottomButtons: showBottomButtons) {
            RecipeRowListEditor(
                items: $recipe.directions,
                newRowID: $newRowID,
                isStandalone: showToolbar,
                newRow: { .emptyRow() }
            ) { $direction, context in
                DirectionEditRowView(
                    direction: $direction,
                    stepNumber: RecipeItemListEditor.stepNumber(forDirectionWith: direction.id, in: recipe.directions),
                    context: context
                )
            }
        } actions: {
            Button("New Step", systemImage: "plus.circle") {
                add(.emptyRow())
            }
            .keyboardShortcut("n", modifiers: [.command])

            Button("New Heading", systemImage: "folder.badge.plus") {
                add(.emptyRow(isHeading: true))
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
        }
    }

    private func add(_ direction: Direction) {
        withAnimation(.easeIn) {
            newRowID = RecipeItemListEditor.append(direction, to: &recipe.directions)
        }
    }
}

// MARK: - Direction Edit Row View

struct DirectionEditRowView: View {
    @Binding var direction: Direction
    let stepNumber: Int?
    let context: RecipeRowContext

    private var placeholder: String {
        direction.isHeadingRow ? "Heading Name" : "Direction text"
    }

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            if let stepNumber {
                Text("\(stepNumber).")
                    .font(.title2)
                    .frame(minWidth: 18, alignment: .trailing)
                    .padding(.trailing, 4)
                    .foregroundStyle(.secondary)
            } else {
                Spacer()
                    .frame(width: 18)
            }

            TextField(placeholder, text: $direction.text, axis: .vertical)
                .font(direction.isHeadingRow ? .headline : .body)
                .fontWeight(direction.isHeadingRow ? .semibold : .regular)
                .lineLimit(direction.isHeadingRow ? 1...2 : 3...13)
                .textFieldStyle(.squareBorder)
                .focused(context.focus, equals: direction.id)
                .modifier(context.keyboardReordering)

            Spacer()
                .frame(width: 2)

            RecipeRowActionButtons(
                context: context,
                previewText: direction.text,
                placeholder: placeholder,
                stepNumber: stepNumber,
                isHeading: direction.isHeadingRow
            )
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 8)
        .background(context.isAlternateRow ? Color(nsColor: .tertiarySystemFill) : .clear)
        .clipShape(.rect(cornerRadius: 6, style: .continuous))
    }
}

#Preview {
    DirectionsEditView(recipe: .constant(SampleData.sampleRecipes[0]))
}

#endif
