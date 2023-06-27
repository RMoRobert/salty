//
//  RecipeIngredientView.swift
//  Salty
//
//  Created by Robert on 6/25/23.
//

import SwiftUI
import RealmSwift

struct RecipeIngredientView: View {
    @ObservedRealmObject var recipe: Recipe
    var body: some View {
        VStack(alignment: .leading) {
            ForEach($recipe.ingredients) { $ingredient in
                if (ingredient.isCategory) {
                    Text(ingredient.name)
                        .fontWeight(.semibold)
                }
                else {
                    let ingText = "\(ingredient.quantity) \(ingredient.name) \(ingredient.notes)".trimmingCharacters(in: .whitespacesAndNewlines)
                    Text(ingText)
                    Spacer().frame(maxHeight: 5)
                }
            }
        }
    }
}

struct RecipeIngredientView_Previews: PreviewProvider {
    static var previews: some View {
        let realm = RecipeLibrary.previewRealm
        let lib = realm.objects(RecipeLibrary.self)
        RecipeIngredientView(recipe: lib.first!.recipes.first!)
    }
}
