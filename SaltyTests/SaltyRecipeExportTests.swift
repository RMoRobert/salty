//
//  SaltyRecipeExportTests.swift
//  SaltyTests
//

import Testing
@testable import Salty

struct SaltyRecipeExportTests {

    @Test func convertToRecipeAssignsNewNestedIds() {
        let export = SaltyRecipeExport(
            id: "export-id",
            name: "Test Cookies",
            directions: [SaltyDirectionExport(from: Direction(id: "dir-1", text: "Bake."))],
            ingredients: [SaltyIngredientExport(from: Ingredient(id: "ing-1", text: "1 cup flour"))],
            notes: [Note(id: "note-1", title: "Tip", content: "Chill the dough.")]
        )

        let recipe = export.convertToRecipe()

        #expect(recipe.id != export.id)
        #expect(recipe.name == export.name)
        #expect(recipe.directions[0].id != "dir-1")
        #expect(recipe.directions[0].text == "Bake.")
        #expect(recipe.ingredients[0].id != "ing-1")
        #expect(recipe.ingredients[0].text == "1 cup flour")
        #expect(recipe.notes[0].id != "note-1")
        #expect(recipe.notes[0].content == "Chill the dough.")
    }

    @Test func exportStructsRoundTripText() {
        let direction = Direction(id: "d1", isHeading: true, text: "Frosting")
        let ingredient = Ingredient(id: "i1", isMain: true, text: "1 cup sugar")

        let exportedDirection = SaltyDirectionExport(from: direction)
        let exportedIngredient = SaltyIngredientExport(from: ingredient)

        #expect(exportedDirection.convertToDirection().text == direction.text)
        #expect(exportedDirection.convertToDirection().isHeading == true)
        #expect(exportedIngredient.convertToIngredient().text == ingredient.text)
        #expect(exportedIngredient.convertToIngredient().isMain == true)
    }
}
