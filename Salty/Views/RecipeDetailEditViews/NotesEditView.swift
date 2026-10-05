//
//  NotesEditView.swift
//  Salty
//
//  Created by Assistant on 1/27/25.
//

import SaltyCore
#if os(macOS)

import SwiftUI

struct NotesEditView: View {
    @Binding var recipe: Recipe
    /// A row that was just added, for the list to scroll to and focus.
    @State private var newRowID: String?

    var showToolbar: Bool = true
    var showBottomButtons: Bool = false

    var body: some View {
        RecipeRowEditorShell(title: "Edit Notes", isStandalone: showToolbar, showsBottomButtons: showBottomButtons) {
            RecipeRowListEditor(
                items: $recipe.notes,
                newRowID: $newRowID,
                isStandalone: showToolbar,
                newRow: { .emptyRow() }
            ) { $note, context in
                NoteEditRowView(note: $note, context: context)
            }
        } actions: {
            Button("New Note", systemImage: "plus.circle") {
                withAnimation(.easeIn) {
                    newRowID = RecipeItemListEditor.append(.emptyRow(), to: &recipe.notes)
                }
            }
            .keyboardShortcut("n", modifiers: [.command])
        }
    }
}

// MARK: - Note Edit Row View

struct NoteEditRowView: View {
    @Binding var note: Note
    let context: RecipeRowContext

    var body: some View {
        HStack {
            VStack {
                HStack {
                    // Icon
                    Image(systemName: "list.triangle")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    // Title field
                    TextField("Note Title", text: $note.title)
                        .textFieldStyle(.squareBorder)
                        .fontWeight(.semibold)
                        .focused(context.focus, equals: note.id)
                        .modifier(context.keyboardReordering)
                }
                HStack {
                    // Icon
                    Image(systemName: "list.triangle")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                        .opacity(0)
                    // Content field (multiline)
                    TextField("Note content", text: $note.content, axis: .vertical)
                        .textFieldStyle(.squareBorder)
                        .lineLimit(2...6)
                        .modifier(context.keyboardReordering)
                }
            }
            RecipeRowActionButtons(context: context, previewText: note.title, placeholder: "Note Title")
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .background(context.isAlternateRow ? Color(nsColor: .tertiarySystemFill) : .clear)
        .clipShape(.rect(cornerRadius: 6, style: .continuous))
    }
}

#Preview {
    NotesEditView(recipe: .constant(SampleData.sampleRecipes[0]))
}

#endif
