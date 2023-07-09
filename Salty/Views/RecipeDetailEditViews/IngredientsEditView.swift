//
//  DirectionsView.swift
//  Salty
//
//  Created by Robert on 7/4/23.
//

import SwiftUI
import RealmSwift

struct IngredientsEditView: View {
    @ObservedRealmObject var recipe: Recipe
    @State private var selectedIngredientIDs = Set<UInt64>()
    private func shouldShowDetailView(for selection: Set<UInt64>) -> Bool {
        print("sel = \(selectedIngredientIDs)")
        if let id = selectedIngredientIDs.first, let _ = recipe.ingredients.first(where: { $0.id == id }) {
            return true
        }
        else {
            return false
        }
    }
    
    var body: some View {
        VStack {
            List(selection: $selectedIngredientIDs) {
                ForEach(recipe.ingredients, id: \.id) { ingredient in
                    Text(ingredient.toString())
                }
                .onDelete(perform: $recipe.ingredients.remove)
                .onMove(perform: $recipe.ingredients.move)
            }
            #if os(macOS)
            .listStyle(.inset(alternatesRowBackgrounds: true))
            #endif
            
            VStack {
                if shouldShowDetailView(for: selectedIngredientIDs) {
                    let ingredient = recipe.ingredients.first(where: {$0.id == selectedIngredientIDs.first! })!
                    IngredientDetailEditView(ingredient: ingredient)
                }
                else {
                    Text("Select ingredient to edit")
                        .foregroundStyle(.secondary)
                }
                
            }
            .frame(minHeight: 60, idealHeight: 100)
            //.padding()
            
            HStack {
                Button(role: .destructive, action: { deleteSelectedIngredients() } ) {
                    Label("Delete", systemImage: "trash")
                        .foregroundColor(.red)
                }
                //.padding()
                
                Button(action: { $recipe.ingredients.append(Ingredient()) } ) {
                    Label("Add", systemImage: "plus")
                }
                //.padding()
            }
        }
    }
    
    func deleteSelectedIngredients() -> () {
        // TODO: there has to be a better way?
        let ids = selectedIngredientIDs.map { $0 }
            ids.forEach { theId in
                if let theIdx = recipe.ingredients.firstIndex(where: {
                    $0.id == theId
                }) {
                    $recipe.ingredients.remove(at: theIdx)
                }
            }
    }
}

struct IngredientDetailEditView: View {
    @ObservedRealmObject var ingredient: Ingredient
    
    var body: some View {
        VStack {
                Toggle(isOn: $ingredient.isCategory) { Text("Category?") }
                    .labelsHidden()
                if !ingredient.isCategory {
                    HStack { // TODO: H or V...
                        TextField("Qty", text: $ingredient.quantity)
                        TextField("Name", text: $ingredient.name)
                        TextField("Notes", text: $ingredient.notes)
                        Toggle(isOn: $ingredient.isMain) { Text("Main?") }
                            .labelsHidden()
                    }
                }
                else {
                    TextField("Name", text: $ingredient.name)
                        .gridCellColumns(3)
                    Spacer()
                }            
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
