//
//  DirectionsView.swift
//  Salty
//
//  Created by Robert on 7/4/23.
//

import SwiftUI
import SharingGRDB

struct IngredientsEditView: View {
    @Dependency(\.defaultDatabase) private var database
    @Binding var recipe: Recipe
    @State private var selectedIndex: Int? = nil
    
    var body: some View {
        VStack {
            List(selection: $selectedIndex) {
                ForEach(Array(recipe.ingredients.enumerated()), id: \.element.id) { index, ingredient in
                    HStack {
                        if ingredient.isHeading {
                            Text(ingredient.text)
                                .font(.headline)
                                .fontWeight(.semibold)
                        } else {
                            Text(ingredient.text)
                        }
                        Spacer()
                    }
                    .tag(index)
                }
                .onDelete { indexSet in
                    try? database.write { db in
                        for index in indexSet.sorted(by: >) {
                            recipe.ingredients.remove(at: index)
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
                        recipe.ingredients.move(fromOffsets: from, toOffset: to)
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
                if let selectedIndex = selectedIndex, selectedIndex < recipe.ingredients.count {
                    IngredientDetailEditView(
                        ingredient: Binding(
                            get: { recipe.ingredients[selectedIndex] },
                            set: { newValue in
                                recipe.ingredients[selectedIndex] = newValue
                                try? database.write { db in
                                    try Recipe.upsert(Recipe.Draft(recipe))
                                        .execute(db)
                                }
                            }
                        )
                    )
                } else {
                    Text("Select an ingredient to edit")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(minHeight: 100, idealHeight: 120)
            .padding()
            
            // Add button
            Button {
                try? database.write { db in
                    recipe.ingredients.append(Ingredient(
                        id: UUID().uuidString,
                        isHeading: false,
                        text: "New ingredient"
                    ))
                    try Recipe.upsert(Recipe.Draft(recipe))
                        .execute(db)
                }
                // Select the newly added item
                selectedIndex = recipe.ingredients.count - 1
            } label: {
                Label("Add Ingredient", systemImage: "plus")
            }
            .padding()
        }
        .frame(minWidth: 400, minHeight: 400)
    }
}

struct IngredientDetailEditView: View {
    @Binding var ingredient: Ingredient
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Edit Ingredient")
                .font(.headline)
            
            if (!ingredient.isMain) {
                Toggle("Is Heading", isOn: $ingredient.isHeading)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text(ingredient.isHeading ? "Heading Text:" : "Ingredient:")
                TextField("Ingredient:", text: $ingredient.text)
                if (!ingredient.isHeading) {                    Toggle("Is Main", isOn: $ingredient.isMain)
                }
            }
        }
        .padding()
    }
}

#Preview {
    IngredientsEditView(recipe: .constant(SampleData.sampleRecipes[0]))
}
