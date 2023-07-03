//
//  DirectionsView.swift
//  Salty
//
//  Created by Robert on 5/29/23.
//

import SwiftUI
import RealmSwift

struct DirectionsEditView: View {
    @ObservedRealmObject var recipe: Recipe
    @State private var selectedDirectionIDs = Set<UInt64>()
    private func shouldShowDetailView(for selection: Set<UInt64>) -> Bool {
        print("sel = \(selectedDirectionIDs)")
        if let id = selectedDirectionIDs.first, let _ = recipe.directions.first(where: { $0.id == id }) {
            return true
        }
        else {
            return false
        }
    }
    
    var body: some View {
        VStack {
            List(selection: $selectedDirectionIDs) {
                ForEach(recipe.directions, id: \.id) { direction in
                    HStack {
                        // has to be a better way, but for now...
                        let idx = (recipe.directions.firstIndex(of: direction)?.magnitude ?? 0) + 1
                        Text("\(idx)" + ".")
                            .font(.title)
                        VStack(alignment: .leading) {
                            if (direction.stepName != "") {
                                Text(direction.stepName)
                                    .fontWeight(.semibold)
                            }
                            Text(direction.text)
                        }
                    }
                }
                .onDelete(perform: $recipe.directions.remove)
                .onMove(perform: $recipe.directions.move)
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
            
            
            VStack {
                if shouldShowDetailView(for: selectedDirectionIDs) {
                    let direction = recipe.directions.first(where: {$0.id == selectedDirectionIDs.first! })!
                    DirectionDetailEditView(direction: direction)
                }
                else {
                    Text("Select direction to edit")
                        .foregroundStyle(.secondary)
                }
                
            }
            .frame(minHeight: 60, idealHeight: 100)
            //.padding()
            
            HStack {
                Button(role: .destructive, action: { deleteSelectedDirections() } ) {
                    Label("Delete", systemImage: "trash")
                        .foregroundColor(.red)
                }
                //.padding()
                
                Button(action: { $recipe.directions.append(Direction()) } ) {
                    Label("Add", systemImage: "plus")
                }
                //.padding()
            }
        
                    
            //                    Button(role: .destructive, action: {
            //                        if let idx = recipe.directions.index(of: direction) {
            //                            $recipe.directions.remove(at: idx)
            //                        } } ) {
            //                            Label("Delete", systemImage: "trash")
            //                                .foregroundColor(.red)
            //                        }
//                        .buttonStyle(.plain)
//                        .labelsHidden()

            
        }
    }
    
    func deleteSelectedDirections() -> () {
        // TODO: there has to be a better way?
        let ids = selectedDirectionIDs.map { $0 }
            ids.forEach { theId in
                if let theIdx = recipe.directions.firstIndex(where: {
                    $0.id == theId
                }) {
                    $recipe.directions.remove(at: theIdx)
                }
            }
    }
}

struct DirectionDetailEditView: View {
    @ObservedRealmObject var direction: Direction
    
    var body: some View {
        VStack {
            TextField("Step description (optional)", text: $direction.stepName)
            TextField("Direction Text", text: $direction.text, axis: .vertical)
                .lineLimit(4)
            
        }
    }
}

struct DirectionsEditView_Previews: PreviewProvider {
    static var previews: some View {
        let realm = RecipeLibrary.previewRealm
        let rl = realm.objects(RecipeLibrary.self)
        let r = rl.randomElement()!.recipes.randomElement()!
        DirectionsEditView(recipe: r)
    }
}
