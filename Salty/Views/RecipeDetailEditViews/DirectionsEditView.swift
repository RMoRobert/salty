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
    //@State private var selectedIngredients = Set<Ingredient.ID>()
    var body: some View {
        VStack {
            ForEach($recipe.directions) { $direction in
                HStack {
                    // has to be a better way, but for now...
                    let idx = (recipe.directions.firstIndex(of: direction)?.magnitude ?? 0) + 1
                    Text("\(idx)" + ".")
                        .font(.title)
                    VStack {
                        TextField("Step description (optional)", text: $direction.stepName)
                        //                        TextField("Step text", text: $direction.text, axis: .vertical)
                        //                            .lineLimit(3)
                        TextField("Direction Text", text: $direction.text, axis: .vertical)
                            .lineLimit(4)
                    }
            #if os(macOS)
                    .textFieldStyle(.squareBorder)
            #endif
                    
                    Button(role: .destructive, action: {
                        if let idx = recipe.directions.index(of: direction) {
                            $recipe.directions.remove(at: idx)
                        } } ) {
                            Label("Delete", systemImage: "trash")
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.plain)
                        .labelsHidden()
                }
            }
            Button(action: { $recipe.directions.append(Direction()) } ) {
                Label("Add", systemImage: "plus")
            }
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
