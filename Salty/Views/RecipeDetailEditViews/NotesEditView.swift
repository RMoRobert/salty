//
//  NotesView.swift
//  Salty
//
//  Created by Robert on 5/29/23.
//

import SwiftUI
import SharingGRDB

struct NotesEditView: View {
    @Dependency(\.defaultDatabase) private var database
    @Binding var recipe: Recipe
    @State private var selectedIndex: Int? = nil
    
    var body: some View {
        VStack {
            List(selection: $selectedIndex) {
                ForEach(Array(recipe.notes.enumerated()), id: \.element.id) { index, note in
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
                            try? database.write { db in
                                recipe.notes.remove(at: index)
                                try Recipe.upsert(Recipe.Draft(recipe))
                                    .execute(db)
                            }
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
                            try? database.write { db in
                                recipe.notes.remove(at: index)
                                try Recipe.upsert(Recipe.Draft(recipe))
                                    .execute(db)
                            }
                            if selectedIndex == index {
                                selectedIndex = nil
                            }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                }
                .onDelete { indexSet in
                    try? database.write { db in
                        for index in indexSet.sorted(by: >) {
                            recipe.notes.remove(at: index)
                        }
                        try Recipe.upsert(Recipe.Draft(recipe))
                            .execute(db)
                    }
                    // Clear selection if deleted item was selected
                    if let selectedIndex = selectedIndex, indexSet.contains(selectedIndex) {
                        self.selectedIndex = nil
                    }
                }
                .onMove { from, to in
                    try? database.write { db in
                        recipe.notes.move(fromOffsets: from, toOffset: to)
                        try Recipe.upsert(Recipe.Draft(recipe))
                            .execute(db)
                    }
                }
            }
            #if os(macOS)
            .listStyle(.inset(alternatesRowBackgrounds: true))
            #endif
            
            // Detail editor
            VStack {
                if let selectedIndex = selectedIndex, selectedIndex < recipe.notes.count {
                    NoteDetailEditView(
                        note: Binding(
                            get: { recipe.notes[selectedIndex] },
                            set: { newValue in
                                recipe.notes[selectedIndex] = newValue
                                try? database.write { db in
                                    try Recipe.upsert(Recipe.Draft(recipe))
                                        .execute(db)
                                }
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
                try? database.write { db in
                    recipe.notes.append(Note(
                        id: UUID().uuidString,
                        title: "",
                        content: "New note content"
                    ))
                    try Recipe.upsert(Recipe.Draft(recipe))
                        .execute(db)
                }
                // Select the newly added item
                selectedIndex = recipe.notes.count - 1
            } label: {
                Label("Add Note", systemImage: "plus")
            }
            .padding()
        }
        #if os(macOS)
        .frame(minWidth: 500, minHeight: 500)
        #endif
        .onAppear {
            // Initialize the view
        }
        .onKeyPress(.delete) {
            if let selectedIndex = selectedIndex, selectedIndex < recipe.notes.count {
                try? database.write { db in
                    recipe.notes.remove(at: selectedIndex)
                    try Recipe.upsert(Recipe.Draft(recipe))
                        .execute(db)
                }
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
