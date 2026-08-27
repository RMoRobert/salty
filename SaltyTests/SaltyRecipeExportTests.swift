//
//  SaltyRecipeExportTests.swift
//  SaltyTests
//

import Testing
@testable import Salty
import SaltyCore

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

    /// Headings orient the cook; they aren't steps, so they must not consume a step number. This used
    /// to number by array index, which made the count skip once per heading ("1, 2, [Sauce], 4").
    @Test func plainTextNumbersOnlyRealSteps() {
        let export = SaltyRecipeExport(
            id: "export-id",
            name: "Pancakes",
            directions: [
                SaltyDirectionExport(from: Direction(id: "d1", text: "Whisk the dry.")),
                SaltyDirectionExport(from: Direction(id: "d2", text: "Fold in the wet.")),
                SaltyDirectionExport(from: Direction(id: "d3", isHeading: true, text: "Sauce")),
                SaltyDirectionExport(from: Direction(id: "d4", text: "Melt the butter.")),
                SaltyDirectionExport(from: Direction(id: "d5", text: "Stir in cream.")),
            ]
        )

        let text = export.plainTextRepresentation

        #expect(text.contains("1. Whisk the dry."))
        #expect(text.contains("2. Fold in the wet."))
        #expect(text.contains("3. Melt the butter."))
        #expect(text.contains("4. Stir in cream."))
        // The heading is printed, but unnumbered -- and nothing skips to 4/5.
        #expect(text.contains("\nSauce\n"))
        #expect(!text.contains("5. Stir in cream."))
    }

    /// The ingredient list has no numbering to get wrong, but its headings follow the same rule: they
    /// print on their own, without the bullet the shopping-relevant lines get.
    @Test func plainTextBulletsIngredientsButNotTheirHeadings() {
        let export = SaltyRecipeExport(
            id: "export-id",
            name: "Pancakes",
            ingredients: [
                SaltyIngredientExport(from: Ingredient(id: "i1", text: "2 cups flour")),
                SaltyIngredientExport(from: Ingredient(id: "i2", isHeading: true, text: "For the glaze")),
                SaltyIngredientExport(from: Ingredient(id: "i3", text: "1 cup sugar")),
            ]
        )

        let text = export.plainTextRepresentation

        #expect(text.contains("• 2 cups flour"))
        #expect(text.contains("• 1 cup sugar"))
        #expect(text.contains("\nFor the glaze\n"))
        #expect(!text.contains("• For the glaze"))
    }
}
