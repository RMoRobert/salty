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
    /// The list's own width, measured so a dragged row's preview can match it.
    @State private var listWidth: CGFloat = 0
    /// Where a dragged row would land, or nil when nothing is being dragged over the list.
    @State private var dropTarget: RecipeItemListEditor.DropTarget?
    /// A row that was just added: scrolled to and focused, then cleared.
    @State private var scrollToNewItem: String?
    @FocusState private var focusedNoteID: String?
    @Environment(\.dismiss) private var dismiss

    var showToolbar: Bool = true
    var showBottomButtons: Bool = false

    var body: some View {
        Group {
            if showToolbar {
                // Standalone view with toolbar (for sheet presentation)
                notesContent
                    .navigationTitle("Edit Notes")
                    .toolbar {
                        ToolbarItemGroup(placement: .automatic) {
                            Button {
                                addNote()
                            } label: {
                                Label("New Note", systemImage: "plus.circle")
                            }
                            .keyboardShortcut("n", modifiers: [.command])
                        }

                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") {
                                dismiss()
                            }
                            .keyboardShortcut(.return, modifiers: [.command])
                        }
                    }
                    .frame(minWidth: 600, idealWidth: 700, maxWidth: 800,
                           minHeight: 500, idealHeight: 600, maxHeight: 800)
                    .presentationSizing(.fitted)
            } else {
                // Embedded view (no toolbar, no frame constraints)
                VStack(spacing: 0) {
                    notesContent
                    if showBottomButtons {
                        bottomActionButtons
                            .padding(.top, 4)
                    }
                }
            }
        }
    }

    private var notesContent: some View {
        ScrollViewReader { proxy in
            notesList
                // Standalone gets its own padding; embedded takes the host's.
                .padding(.horizontal, showToolbar ? nil : 0)
                .padding(.top, showToolbar ? nil : 0)
                .onChange(of: scrollToNewItem) { _, newID in
                    guard let newID else { return }
                    withAnimation(.easeOut) {
                        proxy.scrollTo(newID, anchor: .center)
                    }
                    // Focus once the row has been laid out.
                    Task {
                        try? await Task.sleep(for: .seconds(0.2))
                        focusedNoteID = newID
                        scrollToNewItem = nil
                    }
                }
        }
    }

    private var bottomActionButtons: some View {
        HStack {
            Button {
                addNote()
            } label: {
                Label("New Note", systemImage: "plus.circle")
            }
            .keyboardShortcut("n", modifiers: [.command])

            Spacer()
        }
    }

    private var notesList: some View {
        VStack(spacing: 0) {
            ForEach(recipe.notes) { note in
                let id = note.id
                RecipeListDropIndicator(isActive: dropTarget == .above(id))
                NoteEditRowView(
                    note: RecipeItemListEditor.binding(for: id, in: $recipe.notes, fallback: note),
                    dragPreviewWidth: listWidth,
                    isAlternateRow: RecipeItemListEditor.isAlternateRow(id: id, in: recipe.notes),
                    focusedNoteID: $focusedNoteID,
                    onAdd: { addNote(below: id) },
                    onDelete: { delete(id: id) },
                    onDrop: { droppedID in move(droppedID, to: .above(id)) },
                    onDropTargetChanged: { isTargeted in setDropTarget(.above(id), isTargeted: isTargeted) },
                    onMoveUp: { moveUp(id: id) },
                    onMoveDown: { moveDown(id: id) }
                )
                .id(id)
            }
            RecipeListEndDropZone(
                isActive: dropTarget == .end,
                onDrop: { droppedID in move(droppedID, to: .end) },
                onDropTargetChanged: { isTargeted in setDropTarget(.end, isTargeted: isTargeted) }
            )
        }
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.width
            } action: { width in
                listWidth = width
            }
    }

    // MARK: - Editing

    private func addNote(below id: String) {
        withAnimation(.easeIn) {
            scrollToNewItem = RecipeItemListEditor.insert(.emptyRow(), below: id, in: &recipe.notes)
        }
    }

    private func addNote() {
        withAnimation(.easeIn) {
            scrollToNewItem = RecipeItemListEditor.append(.emptyRow(), to: &recipe.notes)
        }
    }

    private func delete(id: String) {
        withAnimation(.easeIn) {
            RecipeItemListEditor.delete(id: id, from: &recipe.notes)
        }
    }

    private func move(_ id: String, to target: RecipeItemListEditor.DropTarget) -> Bool {
        var moved = false
        withAnimation(.easeIn) {
            moved = RecipeItemListEditor.move(id: id, to: target, in: &recipe.notes)
            dropTarget = nil
        }
        return moved
    }

    private func moveUp(id: String) -> Bool {
        withAnimation(.easeIn) {
            RecipeItemListEditor.moveUp(id: id, in: &recipe.notes)
        }
    }

    private func moveDown(id: String) -> Bool {
        withAnimation(.easeIn) {
            RecipeItemListEditor.moveDown(id: id, in: &recipe.notes)
        }
    }

    /// Only the row currently being hovered clears the indicator: dragging from one row to the next
    /// reports the new row as targeted before the old one reports that it isn't.
    private func setDropTarget(_ target: RecipeItemListEditor.DropTarget, isTargeted: Bool) {
        if isTargeted {
            dropTarget = target
        } else if dropTarget == target {
            dropTarget = nil
        }
    }
}

// MARK: - Note Edit Row View

struct NoteEditRowView: View {
    @Binding var note: Note
    /// Width of the list, so the drag preview can match it.
    let dragPreviewWidth: CGFloat
    let isAlternateRow: Bool
    var focusedNoteID: FocusState<String?>.Binding
    let onAdd: () -> Void
    let onDelete: () -> Void
    /// Returns whether the drop was accepted.
    let onDrop: (String) -> Bool
    let onDropTargetChanged: (Bool) -> Void
    /// Each returns whether the row actually moved.
    let onMoveUp: () -> Bool
    let onMoveDown: () -> Bool

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
                        .focused(focusedNoteID, equals: note.id)
                        .modifier(RecipeRowKeyboardReordering(onMoveUp: onMoveUp, onMoveDown: onMoveDown))
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
                        .modifier(RecipeRowKeyboardReordering(onMoveUp: onMoveUp, onMoveDown: onMoveDown))
                }
            }
            // Action buttons
            HStack(spacing: 4) {
                Button {
                    onAdd()
                } label: {
                    Label("Add", systemImage: "plus.circle.fill")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(Color.green)

                Button {
                    onDelete()
                } label: {
                    Label("Delete", systemImage: "minus.circle.fill")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(.red)

                // Drag handle. The payload is the row's id, so a drop can tell a real row from a
                // stray text drag and never acts on a stale index.
                Label("Drag to Move", systemImage: "line.3.horizontal")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.tertiary)
                    .draggable(note.id) {
                        RecipeRowDragPreview(listWidth: dragPreviewWidth, text: note.title, placeholder: "Note Title")
                    }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .background(isAlternateRow ? Color(nsColor: .tertiarySystemFill) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .dropDestination(for: String.self) { droppedIDs, _ in
            guard let droppedID = droppedIDs.first else { return false }
            return onDrop(droppedID)
        } isTargeted: { isTargeted in
            onDropTargetChanged(isTargeted)
        }
    }
}

#Preview {
    NotesEditView(recipe: .constant(SampleData.sampleRecipes[0]))
}

#endif
