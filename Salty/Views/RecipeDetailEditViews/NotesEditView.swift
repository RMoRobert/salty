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
                        .gridCellColumns(2)
                }
                GridRow {
                    TextEditor(text: $note.text)
                            .lineLimit(2)
                            //.frame(height: 40)
                            .fixedSize(horizontal: false, vertical: true)
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
        NotesEditView(recipe: Recipe())
    }
}
