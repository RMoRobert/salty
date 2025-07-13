//
//  NotesEditView.swift
//  Salty
//
//  Created by Assistant on 1/27/25.
//

import SwiftUI

struct NotesEditView: View {
    @Binding var recipe: Recipe
    @State private var selectedIndex: Int? = nil
    @State private var editingNotes: [Note] = []
    @State private var hasChanges: Bool = false
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack {
            List(selection: $selectedIndex) {
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
                        editingNotes.remove(at: index)
                    }
                    hasChanges = true
                    // Clear selection if deleted item was selected
                    if let selectedIndex = selectedIndex, indexSet.contains(selectedIndex) {
                        self.selectedIndex = nil
                    }
                }
                .onMove { from, to in
                    editingNotes.move(fromOffsets: from, toOffset: to)
                    hasChanges = true
                }
            }
            #if os(macOS)
            .listStyle(.inset(alternatesRowBackgrounds: true))
            #endif
            
            // Detail editor
            VStack {
                if let selectedIndex = selectedIndex, selectedIndex < editingNotes.count {
                    NoteDetailEditView(
                        note: Binding(
                            get: { editingNotes[selectedIndex] },
                            set: { newValue in
                                editingNotes[selectedIndex] = newValue
                                hasChanges = true
                            }
                        )
                    )
                } else {
                    Text("Select a note to edit")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(minHeight: 100, idealHeight: 150)
            .padding()
            
            // Add button
            Button {
                editingNotes.append(Note(
                    id: UUID().uuidString,
                    title: "New Note",
                    content: "Note content"
                ))
                hasChanges = true
                // Select the newly added item
                selectedIndex = editingNotes.count - 1
            } label: {
                Label("Add Note", systemImage: "plus")
            }
            .buttonStyle(.bordered)
            .padding()
        }
        .onAppear {
            editingNotes = recipe.notes
        }
        .onChange(of: editingNotes) { _, _ in
            recipe.notes = editingNotes
        }
        #if os(macOS)
        .frame(minWidth: 500, minHeight: 400)
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
