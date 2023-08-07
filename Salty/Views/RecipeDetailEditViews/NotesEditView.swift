//
//  NotesView.swift
//  Salty
//
//  Created by Robert on 5/29/23.
//

import SwiftUI
import RealmSwift

struct NotesEditView: View {
    @ObservedRealmObject var recipe: Recipe
    
    var body: some View {
        Grid() {
            GridRow {
                Text("Introduction")
                    .gridCellColumns(2)
            }
            GridRow {
                TextEditor(text: $recipe.introduction)
                    .gridCellColumns(2)
                    .lineLimit(2)
                    .frame(height: 40)
                    //.padding()
            }
            ForEach($recipe.notes) { $note in
                GridRow {
                    TextField("Note Name", text: $note.name)
                        .gridCellColumns(1)
                }
                GridRow {
                    TextField("Note Text", text: $note.text, axis: .vertical)
                    Button(role: .destructive, action: {
                        if let idx = recipe.notes.index(of: note) {
                            $recipe.notes.remove(at: idx)
                        } } ) {
                            Label("Delete", systemImage: "trash")
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.plain)
                        .labelsHidden()
                }
                Spacer()
            }
            GridRow {
                Button(action: { $recipe.notes.append(Note()) } ) {
                    Label("Add", systemImage: "plus")
                }
                .gridCellColumns(2)
                .gridCellAnchor(.center)
            }
            
        }
    }
}

struct NotesEditView_Previews: PreviewProvider {
    static var previews: some View {
        let r = Recipe()
        let n1 = Note()
        n1.name = "Note 1"
        n1.text = "This is my note. I'm making it somewhat long so the text might wrap a little, and we will see what happens if that does."
        r.notes.append(n1)
        return NotesEditView(recipe: r)
    }
}
