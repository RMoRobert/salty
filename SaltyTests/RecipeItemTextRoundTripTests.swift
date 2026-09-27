//
//  RecipeItemTextRoundTripTests.swift
//  SaltyTests
//
//  Pins that unedited text keeps item ids (the parsers mint a fresh UUIDv7 per line).
//

import Testing
import Foundation
import SaltyCore

struct RecipeItemTextRoundTripTests {

    private func ingredients() -> [Ingredient] {
        [
            Ingredient(id: SaltyId.new(), isHeading: true, isMain: false, text: "Dough"),
            Ingredient(id: SaltyId.new(), isHeading: false, isMain: true, text: "500 g bread flour"),
            Ingredient(id: SaltyId.new(), isHeading: false, isMain: false, text: "10 g salt"),
        ]
    }

    private func directions() -> [Direction] {
        [
            Direction(id: SaltyId.new(), isHeading: false, text: "Mix and rest for an hour."),
            Direction(id: SaltyId.new(), isHeading: false, text: "Fold every thirty minutes."),
        ]
    }

    // MARK: - Unchanged text keeps identity

    @Test("ingredients survive a round trip through their own formatted text, ids included")
    func unchangedIngredientTextKeepsIds() {
        let original = ingredients()
        let text = IngredientTextParser.formatIngredients(original)

        let result = RecipeItemTextRoundTrip.ingredients(from: text, current: original)

        #expect(result == original)
        #expect(result.map(\.id) == original.map(\.id))
    }

    @Test("directions survive a round trip through their own formatted text, ids included")
    func unchangedDirectionTextKeepsIds() {
        let original = directions()
        let text = DirectionTextParser.formatDirections(original)

        let result = RecipeItemTextRoundTrip.directions(from: text, current: original)

        #expect(result == original)
        #expect(result.map(\.id) == original.map(\.id))
    }

    /// Typing then undoing leaves the editor's `hasChanges` true; the ids must still survive.
    @Test("text edited and then restored is treated as unchanged")
    func editedThenRestoredTextKeepsIds() {
        let original = ingredients()
        var text = IngredientTextParser.formatIngredients(original)
        text += "\n250 g water"                    // typed
        text = IngredientTextParser.formatIngredients(original)   // undone

        #expect(RecipeItemTextRoundTrip.ingredients(from: text, current: original).map(\.id)
                == original.map(\.id))
    }

    // MARK: - Real edits re-parse

    @Test("a changed ingredient line re-parses the list")
    func changedIngredientTextReparses() {
        let original = ingredients()
        let text = IngredientTextParser.formatIngredients(original) + "\n250 g water"

        let result = RecipeItemTextRoundTrip.ingredients(from: text, current: original)

        #expect(result.count == original.count + 1)
        #expect(result.last?.text == "250 g water")
    }

    @Test("a changed direction line re-parses the list")
    func changedDirectionTextReparses() {
        let original = directions()
        let text = DirectionTextParser.formatDirections(original) + "\n\nBake at 240C."

        let result = RecipeItemTextRoundTrip.directions(from: text, current: original)

        #expect(result.count == original.count + 1)
        #expect(result.last?.text == "Bake at 240C.")
    }

    @Test("emptying the text clears the items")
    func emptyTextClearsItems() {
        #expect(RecipeItemTextRoundTrip.ingredients(from: "", current: ingredients()).isEmpty)
        #expect(RecipeItemTextRoundTrip.directions(from: "", current: directions()).isEmpty)
    }

    @Test("empty text against no items is a no-op rather than a change")
    func emptyTextWithNoItems() {
        #expect(RecipeItemTextRoundTrip.ingredients(from: "", current: []).isEmpty)
        #expect(RecipeItemTextRoundTrip.directions(from: "", current: []).isEmpty)
    }

    // MARK: - The Recipe-level convenience

    @Test("applying unchanged text to a recipe leaves it equal to itself")
    func applyingUnchangedTextIsANoOp() {
        var recipe = Recipe(id: SaltyId.new(), name: "Sourdough")
        recipe.ingredients = ingredients()
        recipe.directions = directions()
        let before = recipe

        recipe.applyIngredientsText(IngredientTextParser.formatIngredients(before.ingredients))
        recipe.applyDirectionsText(DirectionTextParser.formatDirections(before.directions))

        // `RecipeWriter.save` uses this equality to decide whether to bump `lastModifiedDate`.
        #expect(recipe == before)
    }

    @Test("applying edited text to a recipe changes it")
    func applyingEditedTextChangesTheRecipe() {
        var recipe = Recipe(id: SaltyId.new(), name: "Sourdough")
        recipe.ingredients = ingredients()
        let before = recipe

        recipe.applyIngredientsText(IngredientTextParser.formatIngredients(before.ingredients) + "\n250 g water")

        #expect(recipe != before)
    }
}
