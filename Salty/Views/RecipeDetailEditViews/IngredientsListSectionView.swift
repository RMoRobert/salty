//
//  IngredientsListSectionView.swift
//  Salty
//
//  The ingredient editor as native List rows: reordering comes from `onMove` instead of the drag
//  handles and drop indicators IngredientsEditView draws itself.
//
//  This has to sit *directly* inside the form's List -- `onMove` only works on a ForEach that is a
//  child of the List, which is why the section header and footer live here rather than in the host.
//  Rows keep their own add and delete buttons: macOS List gives no swipe-to-delete and no editing
//  affordances of its own, so those can't come from the container the way `onMove` can.
//

import SaltyCore
#if os(macOS)

import SwiftUI

struct IngredientsListSectionView: View {
    @Binding var recipe: Recipe
    @FocusState private var focusedIngredientID: String?

    var body: some View {
        ForEach($recipe.ingredients) { $ingredient in
            let id = ingredient.id
            IngredientEditRowView(
                ingredient: $ingredient,
                isAlternateRow: false,
                focusedIngredientID: $focusedIngredientID,
                onAdd: { addIngredient(below: id) },
                onDelete: { delete(id: id) }
            )
            .listRowSeparator(.hidden)
        }
        .onMove { from, to in
            recipe.ingredients.move(fromOffsets: from, toOffset: to)
        }
        .onDelete { offsets in
            recipe.ingredients.remove(atOffsets: offsets)
        }

        BottomActionButtonsView(
            onAddNewIngredient: { append(.emptyRow(isHeading: false)) },
            onAddNewMainIngredient: { append(.emptyRow(isHeading: false, isMain: true)) },
            onAddNewHeading: { append(.emptyRow(isHeading: true)) }
        )
        .listRowSeparator(.hidden)
    }

    // MARK: - Editing

    private func append(_ ingredient: Ingredient) {
        focus(RecipeItemListEditor.append(ingredient, to: &recipe.ingredients))
    }

    private func addIngredient(below id: String) {
        let newID = RecipeItemListEditor.insert(
            .emptyRow(isHeading: false),
            below: id,
            in: &recipe.ingredients
        )
        focus(newID)
    }

    private func delete(id: String) {
        RecipeItemListEditor.delete(id: id, from: &recipe.ingredients)
    }

    private func focus(_ id: String) {
        Task {
            try? await Task.sleep(for: .seconds(0.2))
            focusedIngredientID = id
        }
    }
}

#endif
