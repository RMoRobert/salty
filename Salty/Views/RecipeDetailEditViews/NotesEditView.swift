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
    @State private var selectedIndices: Set<Int> = []
    @State private var editingNotes: [Note] = []
    @State private var hasChanges: Bool = false
    @Environment(\.dismiss) private var dismiss
    
    private func deleteNote(at index: Int) {
        guard index < editingNotes.count else { return }
        editingNotes.remove(at: index)
        hasChanges = true
        
        // Update selection indices after deletion
        var newSelection: Set<Int> = []
        for selectedIndex in selectedIndices {
            if selectedIndex < index {
                // Keep indices before the deleted item unchanged
                newSelection.insert(selectedIndex)
            } else if selectedIndex > index {
                // Decrement indices after the deleted item
                newSelection.insert(selectedIndex - 1)
            }
            // Don't add the deleted index
        }
        selectedIndices = newSelection
    }
    
    private var notesList: some View {
        List(selection: $selectedIndices) {
            ForEach(Array(editingNotes.enumerated()), id: \.element.id) { index, note in
                VStack(alignment: .leading) {
                    if !note.title.isEmpty {
                        Text(note.title)
                            .font(.headline)
                            .fontWeight(.semibold)
                    }
                    Text(note.content)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .lineLimit(3)
                }
                .tag(index)
            }
            .onDelete { indexSet in
                for index in indexSet.sorted(by: >) {
                    deleteNote(at: index)
                }
            }
            .onMove { from, to in
                editingNotes.move(fromOffsets: from, toOffset: to)
                hasChanges = true
            }
        }
        .listStyle(.bordered)
        .alternatingRowBackgrounds()
    }
    
    var body: some View {
        VSplitView {
            // Top section: List of notes
            VStack {
                notesList
                
                // Add and Delete buttons
                HStack {
                    Button {
                        editingNotes.append(Note(
                            id: UUID().uuidString,
                            title: "New note",
                            content: ""
                        ))
                        hasChanges = true
                        selectedIndices = [editingNotes.count - 1]
                    } label: {
                        Label("Add Note", systemImage: "plus")
                    }
                    .padding(.trailing)
                    
                    Button(role: .destructive) {
                        for index in selectedIndices.sorted(by: >) {
                            deleteNote(at: index)
                        }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .disabled(selectedIndices.isEmpty)
                    
                    Spacer()
                }
            }
            .padding()
            .frame(minHeight: 250, idealHeight: 350)
            
            // Bottom section: Detail editor
            VStack {
                if selectedIndices.count == 1, let firstSelectedIndex = selectedIndices.min(), firstSelectedIndex < editingNotes.count {
                    NoteDetailEditView(
                        note: Binding(
                            get: { editingNotes[firstSelectedIndex] },
                            set: { newValue in
                                editingNotes[firstSelectedIndex] = newValue
                                hasChanges = true
                            }
                        )
                    )
                } else {
                    ContentUnavailableView {
                        Text(selectedIndices.count > 1 ?
                             "Select a single note to edit text" : "Select a note to edit"
                        )
                        .font(.body)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(minHeight: 100, idealHeight: 150, maxHeight: 800)
            .padding()
        }
        .navigationTitle("Edit Notes")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    dismiss()
                }
            }
        }
        .onAppear {
            editingNotes = recipe.notes
        }
        .onChange(of: editingNotes) { _, _ in
            recipe.notes = editingNotes
        }
        .frame(minWidth: 500, maxWidth: .infinity,
               minHeight: 500, maxHeight: .infinity)
#if os(macOS)
        .presentationSizing(.fitted)
#endif
    }
}

struct NoteDetailEditView: View {
    @Binding var note: Note
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Edit Note")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Title:")
                TextField("Note title", text: $note.title)
                    .textFieldStyle(.roundedBorder)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Content:")
                TextEditor(text: $note.content)
                    .frame(minHeight: 60)
                    .border(Color.secondary.opacity(0.3))
            }
        }
        .padding()
    }
}

#Preview {
    NotesEditView(recipe: .constant(SampleData.sampleRecipes[0]))
}

#endif
