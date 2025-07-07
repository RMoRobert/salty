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
    @State private var editingIngredients: [Ingredient] = []
    @State private var hasChanges: Bool = false
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack {
            List(selection: $selectedIndex) {
                ForEach(Array(editingIngredients.enumerated()), id: \.element.id) { index, ingredient in
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
                    for index in indexSet.sorted(by: >) {
                        editingIngredients.remove(at: index)
                    }
                    hasChanges = true
                    // Clear selection if deleted item was selected
                    if let selectedIndex = selectedIndex, indexSet.contains(selectedIndex) {
                        self.selectedIndex = nil
                    }
                }
                .onMove { from, to in
                    editingIngredients.move(fromOffsets: from, toOffset: to)
                    hasChanges = true
                }
            }
            #if os(macOS)
            .listStyle(.inset(alternatesRowBackgrounds: true))
            #endif
            
            // Detail editor
            VStack {
                if let selectedIndex = selectedIndex, selectedIndex < editingIngredients.count {
                    IngredientDetailEditView(
                        ingredient: Binding(
                            get: { editingIngredients[selectedIndex] },
                            set: { newValue in
                                editingIngredients[selectedIndex] = newValue
                                hasChanges = true
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
                editingIngredients.append(Ingredient(
                    id: UUID().uuidString,
                    isHeading: false,
                    text: "New ingredient"
                ))
                hasChanges = true
                // Select the newly added item
                selectedIndex = editingIngredients.count - 1
            } label: {
                Label("Add Ingredient", systemImage: "plus")
                    .buttonStyle(.bordered)
            }
            .buttonStyle(.bordered)
            .padding()
        }
        .onAppear {
            editingIngredients = recipe.ingredients
        }
        .onChange(of: editingIngredients) { _, _ in
            recipe.ingredients = editingIngredients
        }
        #if os(macOS)
        .frame(minWidth: 400, minHeight: 400)
        #endif
    }
}

struct IngredientDetailEditView: View {
    @Binding var ingredient: Ingredient
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Edit Ingredient")
                .font(.headline)
            
            if (!ingredient.isMain) {
                Toggle("Is heading", isOn: $ingredient.isHeading)
            }
            
            VStack(alignment: .leading, spacing: 8) {
            #if os(iOS)
                TextField("Ingredient:", text: $ingredient.text)
                    .textFieldStyle(.roundedBorder)
                if (!ingredient.isHeading) {                    Toggle("Is main", isOn: $ingredient.isMain)
                }
            #else
                Text(ingredient.isHeading ? "Heading Text:" : "Ingredient:")
                HStack {
                    TextField("Ingredient:", text: $ingredient.text)
                    if (!ingredient.isHeading) {                    Toggle("Is Main", isOn: $ingredient.isMain)
                    }
                }
            #endif
            }
        }
        .padding()
    }
}

#Preview {
    IngredientsEditView(recipe: .constant(SampleData.sampleRecipes[0]))
}
