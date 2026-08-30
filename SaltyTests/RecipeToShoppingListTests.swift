//
//  RecipeToShoppingListTests.swift
//  SaltyTests
//
//  Covers the recipe → shopping list path: which ingredient lines are offered, the quantity-blind
//  comparison that decides what the destination list already covers, and where added lines land.
//

import Testing
import Foundation
@testable import Salty
import SaltyCore

struct RecipeToShoppingListCandidateTests {

    private func recipe(_ ingredients: [Ingredient]) -> Recipe {
        Recipe(id: "recipe-1", name: "Chili", ingredients: ingredients)
    }

    private func ingredient(_ id: String, _ text: String, isHeading: Bool = false) -> Ingredient {
        Ingredient(id: id, isHeading: isHeading, text: text)
    }

    @Test func dropsHeadingsAndKeepsThemAsGroupNames() {
        let candidates = RecipeToShoppingList.candidates(from: recipe([
            ingredient("h1", "For the chili", isHeading: true),
            ingredient("i1", "1 lb ground beef"),
            ingredient("h2", "For the topping", isHeading: true),
            ingredient("i2", "1 cup sour cream")
        ]))

        #expect(candidates.map(\.id) == ["i1", "i2"])
        #expect(candidates[0].groupHeading == "For the chili")
        #expect(candidates[1].groupHeading == "For the topping")
    }

    @Test func ungroupedIngredientsHaveNoGroupHeading() {
        let candidates = RecipeToShoppingList.candidates(from: recipe([
            ingredient("i1", "2 eggs")
        ]))

        #expect(candidates.count == 1)
        #expect(candidates[0].groupHeading == nil)
    }

    @Test func skipsBlankLines() {
        let candidates = RecipeToShoppingList.candidates(from: recipe([
            ingredient("i1", "   "),
            ingredient("i2", "Salt")
        ]))

        #expect(candidates.map(\.id) == ["i2"])
    }

    @Test func appliesTheActiveScaleToTheAddedText() {
        let candidates = RecipeToShoppingList.candidates(
            from: recipe([ingredient("i1", "2 cups flour")]),
            scaleFactor: 0.5
        )

        // "1 cups", not "1 cup": IngredientScaler leaves the unit exactly as the recipe wrote it,
        // which is what the scaled ingredients list already displays. Asserted as-is so this test
        // tracks the scaler rather than duplicating a rule about units.
        #expect(candidates[0].text == "1 cups flour")
    }

    @Test func unscaledTextIsUntouched() {
        let candidates = RecipeToShoppingList.candidates(
            from: recipe([ingredient("i1", "1 1/2 cups whole milk")])
        )

        #expect(candidates[0].text == "1 1/2 cups whole milk")
    }
}

struct RecipeToShoppingListDuplicateTests {

    private func item(_ text: String, done: Bool = false, heading: Bool = false) -> ShoppingListListContents {
        ShoppingListListContents(id: UUID().uuidString, isCompleted: done, isHeading: heading, text: text)
    }

    @Test func ignoresQuantitiesAndUnits() {
        #expect(RecipeToShoppingList.isAlreadyOnList("2 cups flour", existingItems: [item("flour")]))
        #expect(RecipeToShoppingList.isAlreadyOnList("flour", existingItems: [item("3 tbsp flour")]))
    }

    @Test func matchesGeneralAgainstSpecificInBothDirections() {
        // The list has the general form, the recipe wants the specific one (and vice versa).
        #expect(RecipeToShoppingList.isAlreadyOnList("1 cup all-purpose flour", existingItems: [item("flour")]))
        #expect(RecipeToShoppingList.isAlreadyOnList("flour", existingItems: [item("all purpose flour")]))
    }

    @Test func ignoresPrepDetailAfterACommaAndInParentheses() {
        #expect(RecipeToShoppingList.isAlreadyOnList("3 cloves garlic, minced", existingItems: [item("garlic")]))
        #expect(RecipeToShoppingList.isAlreadyOnList("2 onions (about 1 lb), diced", existingItems: [item("onion")]))
    }

    @Test func matchesAcrossPlurals() {
        #expect(RecipeToShoppingList.isAlreadyOnList("2 eggs", existingItems: [item("egg")]))
        #expect(RecipeToShoppingList.isAlreadyOnList("4 tomatoes", existingItems: [item("tomato")]))
    }

    @Test func doesNotMatchDifferentIngredients() {
        #expect(!RecipeToShoppingList.isAlreadyOnList("1 cup olive oil", existingItems: [item("vegetable oil")]))
        #expect(!RecipeToShoppingList.isAlreadyOnList("1 tsp salt", existingItems: [item("salted butter")]))
    }

    /// The pair that a plain subset test gets wrong: structurally "butter" sits inside "peanut
    /// butter" exactly as "flour" sits inside "all-purpose flour", but only one of them is the same
    /// thing to buy. An unrecognized extra word means a different ingredient.
    @Test func aQualifiedIngredientIsTheSameOneButANamedVarietyIsNot() {
        #expect(RecipeToShoppingList.isAlreadyOnList("2 cups all-purpose flour", existingItems: [item("flour")]))
        #expect(RecipeToShoppingList.isAlreadyOnList("1 stick unsalted butter", existingItems: [item("butter")]))

        #expect(!RecipeToShoppingList.isAlreadyOnList("2 tbsp butter", existingItems: [item("peanut butter")]))
        #expect(!RecipeToShoppingList.isAlreadyOnList("1 cup sour cream", existingItems: [item("cream")]))
        #expect(!RecipeToShoppingList.isAlreadyOnList("2 tbsp wine", existingItems: [item("white wine vinegar")]))
    }

    @Test func headingsNeverCount() {
        // A section named after the recipe shouldn't make every line look already-present.
        #expect(!RecipeToShoppingList.isAlreadyOnList("2 cups flour", existingItems: [item("flour", heading: true)]))
    }

    @Test func alreadyBoughtItemsDoNotBlock() {
        // Checked off means bought. A new recipe needing the same thing still needs it bought again,
        // and a fully shopped list must not swallow every addition.
        #expect(!RecipeToShoppingList.isAlreadyOnList("2 cups flour", existingItems: [item("flour", done: true)]))
    }

    @Test func linesThatReduceToNothingNeverMatch() {
        // "1 large" is all quantity and size words -- nothing identifying is left, so claiming a
        // match against an equally empty row would be arbitrary.
        #expect(!RecipeToShoppingList.isAlreadyOnList("1 large", existingItems: [item("2 medium")]))
    }

    @Test func emptyListMatchesNothing() {
        #expect(!RecipeToShoppingList.isAlreadyOnList("2 cups flour", existingItems: []))
    }
}

@MainActor
struct AddToShoppingListNamingTests {

    private func list(_ name: String) -> ShoppingList {
        ShoppingList(id: UUID().uuidString, name: name, isFreeform: false)
    }

    @Test func usesThePlainNameWhenItIsFree() {
        #expect(AddToShoppingListViewModel.availableNewListName(among: []) == "New List")
        #expect(AddToShoppingListViewModel.availableNewListName(among: [list("Costco")]) == "New List")
    }

    @Test func countsPastNamesThatAreTaken() {
        #expect(AddToShoppingListViewModel.availableNewListName(among: [list("New List")]) == "New List 2")
        #expect(
            AddToShoppingListViewModel.availableNewListName(
                among: [list("New List"), list("New List 2")]
            ) == "New List 3"
        )
    }

    @Test func ignoresCaseAndSurroundingSpaceWhenDecidingWhatIsTaken() {
        #expect(AddToShoppingListViewModel.availableNewListName(among: [list("  new list ")]) == "New List 2")
    }
}

struct RecipeToShoppingListAddingTests {

    /// Predictable ids so assertions can be about structure rather than UUIDs.
    private func sequentialIds() -> () -> String {
        var next = 0
        return {
            next += 1
            return "new-\(next)"
        }
    }

    private func candidate(_ id: String, _ text: String) -> RecipeToShoppingList.CandidateItem {
        RecipeToShoppingList.CandidateItem(id: id, text: text)
    }

    private func item(_ id: String, _ text: String, heading: Bool = false) -> ShoppingListListContents {
        ShoppingListListContents(id: id, isHeading: heading, text: text)
    }

    @Test func appendsAHeadingAndTheChosenLines() {
        let result = RecipeToShoppingList.adding(
            [candidate("c1", "2 cups flour"), candidate("c2", "1 tsp salt")],
            to: [item("e1", "milk")],
            underHeading: "Pancakes",
            makeId: sequentialIds()
        )

        #expect(result.map(\.text) == ["milk", "Pancakes", "2 cups flour", "1 tsp salt"])
        #expect(result[1].isHeading == true)
        #expect(result[2].isHeading == false)
        // The row that was already there is untouched, id included.
        #expect(result[0].id == "e1")
    }

    @Test func extendsAnExistingSectionForTheSameRecipe() {
        let existing = [
            item("h1", "Pancakes", heading: true),
            item("e1", "2 cups flour"),
            item("h2", "Dairy", heading: true),
            item("e2", "butter")
        ]

        let result = RecipeToShoppingList.adding(
            [candidate("c1", "1 tsp salt")],
            to: existing,
            underHeading: "Pancakes",
            makeId: sequentialIds()
        )

        // Lands at the end of the Pancakes section, not after "butter", and adds no second heading.
        #expect(result.map(\.text) == ["Pancakes", "2 cups flour", "1 tsp salt", "Dairy", "butter"])
        #expect(result.count(where: { $0.isHeading ?? false }) == 2)
    }

    @Test func matchesAnExistingSectionIgnoringCase() {
        let result = RecipeToShoppingList.adding(
            [candidate("c1", "1 tsp salt")],
            to: [item("h1", "PANCAKES", heading: true), item("e1", "flour")],
            underHeading: "Pancakes",
            makeId: sequentialIds()
        )

        #expect(result.map(\.text) == ["PANCAKES", "flour", "1 tsp salt"])
    }

    @Test func extendsASectionThatSitsAtTheEndOfTheList() {
        let result = RecipeToShoppingList.adding(
            [candidate("c1", "1 tsp salt")],
            to: [item("e1", "milk"), item("h1", "Pancakes", heading: true), item("e2", "flour")],
            underHeading: "Pancakes",
            makeId: sequentialIds()
        )

        #expect(result.map(\.text) == ["milk", "Pancakes", "flour", "1 tsp salt"])
    }

    @Test func appendsWithoutAHeadingWhenTheRecipeIsUnnamed() {
        let result = RecipeToShoppingList.adding(
            [candidate("c1", "1 tsp salt")],
            to: [item("e1", "milk")],
            underHeading: nil,
            makeId: sequentialIds()
        )

        #expect(result.map(\.text) == ["milk", "1 tsp salt"])
        #expect(result.count(where: { $0.isHeading ?? false }) == 0)
    }

    @Test func addingNothingLeavesTheListAlone() {
        let existing = [item("e1", "milk")]
        let result = RecipeToShoppingList.adding([], to: existing, underHeading: "Pancakes")

        #expect(result == existing)
    }

    @Test func addedRowsStartUnchecked() {
        let result = RecipeToShoppingList.adding(
            [candidate("c1", "1 tsp salt")],
            to: [],
            underHeading: nil,
            makeId: sequentialIds()
        )

        #expect(result[0].isCompleted == false)
    }
}
