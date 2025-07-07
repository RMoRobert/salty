//
//  NotesView.swift
//  Salty
//
//  Created by Robert on 5/29/23.
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
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            if !note.title.isEmpty {
                                Text(note.title)
                                    .font(.headline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.primary)
                            } else {
                                Text("Untitled Note")
                                    .font(.headline)
                                    .fontWeight(.semibold)
                                    .foregroundColor(.secondary)
                            }
                            Text(note.content)
                                .font(.body)
                                .foregroundColor(.secondary)
                                .lineLimit(2)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        
                        Button(role: .destructive) {
                            editingNotes.remove(at: index)
                            hasChanges = true
                            if selectedIndex == index {
                                selectedIndex = nil
                            }
                        } label: {
                            Image(systemName: "trash")
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.plain)
                        .allowsHitTesting(true)
                        .onTapGesture {
                            // Prevent the tap from selecting the row
                        }
                    }
                    .tag(index)
                    .contextMenu {
                        Button(role: .destructive) {
                            editingNotes.remove(at: index)
                            hasChanges = true
                            if selectedIndex == index {
                                selectedIndex = nil
                            }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
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
            .frame(minHeight: 120, idealHeight: 150)
            .padding()
            
            // Add button
            Button {
                editingNotes.append(Note(
                    id: UUID().uuidString,
                    title: "",
                    content: "New note content"
                ))
                hasChanges = true
                // Select the newly added item
                selectedIndex = editingNotes.count - 1
            } label: {
                Label("Add Note", systemImage: "plus")
            }
            .padding()
        }
        #if os(macOS)
        .frame(minWidth: 500, minHeight: 500)
        #endif
        .onAppear {
            editingNotes = recipe.notes
        }
        .onChange(of: editingNotes) { _, _ in
            recipe.notes = editingNotes
        }
        .onKeyPress(.delete) {
            if let selectedIndex = selectedIndex, selectedIndex < editingNotes.count {
                editingNotes.remove(at: selectedIndex)
                hasChanges = true
                self.selectedIndex = nil
            }
            return .handled
        }
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
                    .font(.subheadline)
                    .fontWeight(.medium)
                TextField("Note title", text: $note.title)
                    .textFieldStyle(.roundedBorder)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Content:")
                    .font(.subheadline)
                    .fontWeight(.medium)
                TextField("Note content", text: $note.content, axis: .vertical)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(4...8)
            }
        }
        .padding()
        //.background(Color(.systemGray6))
        //.cornerRadius(8)
    }
}

#Preview {
    NotesEditView(recipe: .constant(SampleData.sampleRecipes[0]))
}
