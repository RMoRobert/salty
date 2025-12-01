//
//  NotesEditView.swift
//  Salty
//
//  Created by Assistant on 1/27/25.
//

#if os(macOS)

import SwiftUI

struct NotesEditView: View {
    @Binding var recipe: Recipe
    @State private var editingNotes: [Note] = []
    @State private var draggedItem: Note?
    @State private var dropTargetIndex: Int?
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
                                addNewNote()
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
        .onAppear {
            editingNotes = recipe.notes
        }
        .onChange(of: editingNotes) { _, newValue in
            recipe.notes = newValue
        }
        .onDisappear {
            recipe.notes = editingNotes
        }
    }
    
    private var notesContent: some View {
        ScrollViewReader { proxy in
            Group {
                if showToolbar {
                    // Standalone view - add padding
                    notesList
                        .padding(.horizontal)
                        .padding(.top)
                } else {
                    // Embedded view - no extra padding
                    notesList
                }
            }
            .onChange(of: scrollToNewItem) { _, newID in
                if let newID = newID {
                    withAnimation(.easeOut) {
                        proxy.scrollTo(newID, anchor: .center)
                    }
                    // Set focus after scrolling
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        focusedNoteID = newID
                        scrollToNewItem = nil
                    }
                }
            }
        }
    }
    
    private var bottomActionButtons: some View {
        HStack {
            Button {
                addNewNote()
            } label: {
                Label("New Note", systemImage: "plus.circle")
            }
            .keyboardShortcut("n", modifiers: [.command])
            
            Spacer()
        }
    }
    
    private var notesList: some View {
        VStack(spacing: 0) {
            ForEach(editingNotes, id: \.id) { note in
                if let index = editingNotes.firstIndex(where: { $0.id == note.id }),
                   index < editingNotes.count {
                    dropIndicator(for: index)
                    noteRow(at: index)
                }
            }
            dropIndicatorAtEnd
        }
    }
    
    @ViewBuilder
    private func dropIndicator(for index: Int) -> some View {
        if let dropTarget = dropTargetIndex, dropTarget == index {
            Rectangle()
                .fill(Color.accentColor)
                .frame(height: 3)
                .padding(.horizontal, 20)
                .transition(.opacity.combined(with: .scale))
        }
    }
    
    @ViewBuilder
    private var dropIndicatorAtEnd: some View {
        let currentCount = editingNotes.count
        if let dropTarget = dropTargetIndex, dropTarget == currentCount, currentCount >= 0 {
            Rectangle()
                .fill(Color.primary)
                .frame(height: 2)
                .padding(.horizontal, 20)
                .transition(.opacity.combined(with: .scale))
        }
    }
    
    @ViewBuilder
    private func noteRow(at index: Int) -> some View {
        // Ensure index is valid before accessing
        if index >= 0 && index < editingNotes.count {
            let note = editingNotes[index]
            // Create a safe binding that checks bounds
            let noteBinding = Binding<Note>(
                get: {
                    guard index >= 0 && index < editingNotes.count else {
                        return note
                    }
                    return editingNotes[index]
                },
                set: { newValue in
                    guard index >= 0 && index < editingNotes.count else { return }
                    editingNotes[index] = newValue
                }
            )
            // Alternating background colors for list effect
            let backgroundColor = (index % 2 == 0 || editingNotes.count < 3)
                ? Color.clear
                : Color(nsColor: .tertiarySystemFill)
            NoteEditRowView(
                note: noteBinding,
                index: index,
                backgroundColor: backgroundColor,
                onAdd: { addNoteAfter(index) },
                onDelete: { deleteNote(at: index) },
                onMove: { fromIndex, toIndex in
                    moveNote(from: fromIndex, to: toIndex)
                },
                onDragStart: {
                    draggedItem = note
                },
                onDragEnd: {
                    draggedItem = nil
                    dropTargetIndex = nil
                },
                onDropTargetChanged: { targetIndex in
                    dropTargetIndex = targetIndex
                }
            )
            .focused($focusedNoteID, equals: note.id)
            .id(note.id)
        }
    }
    
    private func addNoteAfter(_ index: Int) {
        let newNote = Note(
            id: UUID().uuidString,
            title: "",
            content: ""
        )
        withAnimation(.easeIn) {
            editingNotes.insert(newNote, at: index + 1)
        }
        scrollToNewItem = newNote.id
        // Set focus after a brief delay to ensure the view is rendered
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            focusedNoteID = newNote.id
        }
    }
    
    private func deleteNote(at index: Int) {
        guard index >= 0 && index < editingNotes.count else { return }
        // Clear or adjust drop target if needed
        if let dropTarget = dropTargetIndex {
            if dropTarget == index {
                dropTargetIndex = nil
            } else if dropTarget > index {
                dropTargetIndex = dropTarget - 1
            }
        }
        withAnimation(.easeIn) {
            editingNotes.remove(at: index)
        }
    }
    
    private func moveNote(from fromIndex: Int, to toIndex: Int) {
        withAnimation(.easeIn) {
            editingNotes.move(fromOffsets: IndexSet(integer: fromIndex), toOffset: toIndex)
        }
    }
    
    private func addNewNote() {
        let newNote = Note(
            id: UUID().uuidString,
            title: "",
            content: ""
        )
        withAnimation(.easeIn) {
            editingNotes.append(newNote)
        }
        scrollToNewItem = newNote.id
        // Set focus after a brief delay to ensure the view is rendered
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            focusedNoteID = newNote.id
        }
    }
}

// MARK: - Note Edit Row View

struct NoteEditRowView: View {
    @Binding var note: Note
    let index: Int
    let backgroundColor: Color
    let onAdd: () -> Void
    let onDelete: () -> Void
    let onMove: (Int, Int) -> Void
    let onDragStart: () -> Void
    let onDragEnd: () -> Void
    let onDropTargetChanged: (Int?) -> Void
    
    @State private var isDragging = false
    @State private var isDropTarget = false
    
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
                .foregroundStyle(Color.accentColor)
                
                Button {
                    onDelete()
                } label: {
                    Label("Delete", systemImage: "minus.circle.fill")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(.red)
                
                // Drag handle
                Label("Drag to Move", systemImage: "line.3.horizontal")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.tertiary)
                    .draggable(String(index)) {
                        Label("Drag to Move", systemImage: "line.3.horizontal")
                            .labelStyle(.iconOnly)
                            .foregroundStyle(.tertiary)
                    }
                    .onDrag {
                        isDragging = true
                        onDragStart()
                        return NSItemProvider(object: String(index) as NSString)
                    }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .opacity(isDragging ? 0.4 : 1.0)
        .scaleEffect(isDragging ? 0.95 : 1.0)
        .animation(.spring, value: isDragging)
        .dropDestination(for: String.self) { draggedIndices, location in
            guard let draggedIndexString = draggedIndices.first,
                  let draggedIndex = Int(draggedIndexString),
                  draggedIndex != index else {
                isDragging = false
                onDragEnd()
                return false
            }
            onMove(draggedIndex, draggedIndex < index ? index + 1 : index)
            isDragging = false
            onDragEnd()
            return true
        } isTargeted: { isTargeted in
            isDropTarget = isTargeted
            onDropTargetChanged(isTargeted ? index : nil)
        }
    }
}

#Preview {
    NotesEditView(recipe: .constant(SampleData.sampleRecipes[0]))
}

#endif
