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
        List($recipe.directions) { $direction in
            VStack {
                HStack {
                    let idx = recipe.directions.firstIndex(of: direction)
                    Text((idx?.description ?? "0") + ".")
                        .font(.title)
                    VStack {
                        TextField("Step description (optional)", text: $direction.stepName)
                        TextField("Step text", text: $direction.text, axis: .vertical)
                            .lineLimit(3)
                    }
                    .textFieldStyle(.squareBorder)
                }
            }
            Spacer()
        }
    }
}

struct DirectionsEditView_Previews: PreviewProvider {
    static var previews: some View {
        let realm = RecipeLibrary.previewRealm
        let r = realm.objects(Recipe.self)
        DirectionsEditView(recipe: r.first!)
    }
}
