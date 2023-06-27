//
//  IngredientsView.swift
//  Salty
//
//  Created by Robert on 5/29/23.
//

import SwiftUI
import RealmSwift

struct IngredientsEditView: View {
    @ObservedRealmObject var recipe: Recipe
    //@State private var selectedIngredients = Set<Ingredient.ID>()
    var body: some View {
        Grid(verticalSpacing: 1) {
            if (recipe.ingredients.count > 0) {
                GridRow {
                    Group {
                        Text("Is Category?")
                        Text("Quantity")
                        Text("Ingredient Name")
                        Text("Notes")
                        Text("Main?")
                    }
                    .font(.footnote)
                }
            }
            else {
                Text("(none)")
            }
            ForEach($recipe.ingredients) { $ingredient in
                GridRow {
                    Toggle(isOn: $ingredient.isCategory) { Text("Category?") }
                        .labelsHidden()
                    if !ingredient.isCategory {
                        TextField("Qty", text: $ingredient.quantity)
                        TextField("Name", text: $ingredient.name)
                        TextField("Notes", text: $ingredient.notes)
                        Toggle(isOn: $ingredient.isMain) { Text("Main?") }
                            .labelsHidden()
                    }
                    else {
                        TextField("Name", text: $ingredient.name)
                            .gridCellColumns(3)
                        Spacer()
                    }
                    Button(role: .destructive, action: {
                        if let idx = recipe.ingredients.index(of: ingredient) {
                            $recipe.ingredients.remove(at: idx)
                        } } ) {
                            Label("Delete", systemImage: "trash")
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.plain)
                        .labelsHidden()
                }
            }
            GridRow {
                Button(action: { $recipe.ingredients.append(Ingredient()) } ) {
                    Label("Add", systemImage: "plus")
                }
            }
            .gridCellColumns(6)
            .gridCellAnchor(.center)
        }
    }
}

struct IngredientsEditView_Previews: PreviewProvider {
    static var previews: some View {
        let realm = RecipeLibrary.previewRealm
        let rl = realm.objects(RecipeLibrary.self)
        let r = rl.randomElement()!.recipes.randomElement()!
        IngredientsEditView(recipe: r)
    }
}
