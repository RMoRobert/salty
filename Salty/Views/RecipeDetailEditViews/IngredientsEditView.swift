//
//  DirectionsView.swift
//  Salty
//
//  Created by Robert on 7/4/23.
//

#if os(macOS)

import SwiftUI

struct IngredientsEditView: View {
    @Binding var recipe: Recipe
    @State private var selectedIndices: Set<Int> = []
    @State private var editingIngredients: [Ingredient] = []
    @State private var hasChanges: Bool = false
    @State private var scrollToNewItem: Bool = false
    @Environment(\.dismiss) private var dismiss
    
    private func deleteIngredient(at index: Int) {
        guard index < editingIngredients.count else { return }
        editingIngredients.remove(at: index)
        hasChanges = true
        
        // Update selection indices after deletion
        var newSelection: Set<Int> = []
        for selectedIndex in selectedIndices {
            if selectedIndex < index {
                // Keep indices before the deleted item unchanged
                newSelection.insert(selectedIndex)
            } else if selectedIndex > index {
                // Decrement indices after the deleted item
                newSelection.insert(selectedIndex - 1)
            }
            // Don't add the deleted index
        }
        selectedIndices = newSelection
    }
    
    private var ingredientsList: some View {
        ScrollViewReader { proxy in
            List(selection: $selectedIndices) {
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
                    .id(index)
                }
                .onDelete { indexSet in
                    for index in indexSet.sorted(by: >) {
                        deleteIngredient(at: index)
                    }
                }
                .onMove { from, to in
                    editingIngredients.move(fromOffsets: from, toOffset: to)
                    hasChanges = true
                }
            }
            .listStyle(.bordered)
            .alternatingRowBackgrounds()
            .onChange(of: scrollToNewItem) { _, shouldScroll in
                if shouldScroll, let lastIndex = editingIngredients.indices.last {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(lastIndex, anchor: .bottom)
                    }
                    scrollToNewItem = false
                }
            }
        }
    }
    
    var body: some View {
        VSplitView {
                // Top section: List of ingredients
                VStack {
                    ingredientsList
                    
                    // Add and Delete buttons
                    HStack {
                        Button {
                            editingIngredients.append(Ingredient(
                                id: UUID().uuidString,
                                isHeading: false,
                                text: "New ingredient"
                            ))
                            hasChanges = true
                            selectedIndices = [editingIngredients.count - 1]
                            scrollToNewItem = true
                        } label: {
                            Label("Add Ingredient", systemImage: "plus")
                        }
                        .padding(.trailing)
                        
                        Button {
                            editingIngredients.append(Ingredient(
                                id: UUID().uuidString,
                                isHeading: true,
                                text: "New heading"
                            ))
                            hasChanges = true
                            selectedIndices = [editingIngredients.count - 1]
                            scrollToNewItem = true
                        } label: {
                            Label("Add Heading", systemImage: "folder.badge.plus")
                        }
                        .padding(.trailing)
                        
                        Button(role: .destructive) {
                            for index in selectedIndices.sorted(by: >) {
                                deleteIngredient(at: index)
                            }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        .disabled(selectedIndices.isEmpty)
                        
                        Spacer()
                    }
                }
                .padding()
                .frame(minHeight: 250, idealHeight: 350)
                
                // Bottom section: Detail editor
                VStack {
                    if selectedIndices.count == 1, let firstSelectedIndex = selectedIndices.min(), firstSelectedIndex < editingIngredients.count {
                        IngredientDetailEditView(
                            ingredient: Binding(
                                get: { editingIngredients[firstSelectedIndex] },
                                set: { newValue in
                                    editingIngredients[firstSelectedIndex] = newValue
                                    hasChanges = true
                                }
                            )
                        )
                    } else {
                        ContentUnavailableView {
                            Text(selectedIndices.count > 1 ?
                                 "Select a single item to edit" : "Select an ingredient to edit"
                            )
                                .font(.body)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(minHeight: 75, idealHeight: 90, maxHeight: 400)
                .padding()
            }
            .navigationTitle("Edit Ingredients")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        .onAppear {
            editingIngredients = recipe.ingredients
        }
        .onChange(of: editingIngredients) { _, _ in
            recipe.ingredients = editingIngredients
        }
        .frame(minWidth: 500, minHeight: 500)
    }
}

struct IngredientDetailEditView: View {
    @Binding var ingredient: Ingredient
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Edit Ingredient")
                .font(.headline)
           
            VStack(alignment: .leading, spacing: 8) {
                Text(ingredient.isHeading ? "Heading Text:" : "Ingredient:")
                HStack {
                    TextField("Ingredient:", text: $ingredient.text)
                    if (!ingredient.isHeading) {
                        Toggle("Is Main", isOn: $ingredient.isMain)
                    }
                }
            }
        }
        .padding()
    }
}

#Preview {
    IngredientsEditView(recipe: .constant(SampleData.sampleRecipes[0]))
}

#endif
