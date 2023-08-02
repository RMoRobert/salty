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
    @Environment(\.dismiss) private var dismiss
    
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
            
            VStack {
                HStack {
                    Button(role: .destructive, action: { deleteSelectedIngredients() } ) {
                        Label("Delete", systemImage: "trash")
                            .foregroundColor(.red)
                    }
                    //.padding()
                    
                    Button(action: {
                        let newIng = Ingredient()
                        newIng.name = "New Ingredient"
                        $recipe.ingredients.append(newIng)
                    } ) {
                        Label("Add", systemImage: "plus")
                    }
                    //.padding()
                }
                Button("Done") {
                    dismiss()
                }
                .buttonStyle(.link)
            }
            .padding()
        }
        .frame(minWidth: 300, minHeight: 400)
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
                Toggle(isOn: $ingredient.isCategory) { Text("Is Category?") }
                if !ingredient.isCategory {
                    HOrVStack {
                        TextField("Qty", text: $ingredient.quantity)
                            .frame(idealWidth: 60, maxWidth: 200)
                        TextField("Name", text: $ingredient.name)
                        TextField("Notes", text: $ingredient.notes)
                        Toggle(isOn: $ingredient.isMain) { Text("Main?") }
                            //.labelsHidden()
                    }
                    .padding()
                }
                else {
                    TextField("Name", text: $ingredient.name)
                        .padding()
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
