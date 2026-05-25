//
//  IngredientParseQuantityTests.swift
//  SaltyTests
//

import Testing
@testable import Salty

struct IngredientParseQuantityTests {

    @Test func parsesCupAndRemainder() {
        let ingredient = Ingredient(id: "1", text: "2 cups flour")
        let parsed = ingredient.parseQuantity()
        #expect(parsed.quantity == "2 cups")
        #expect(parsed.remainder == "flour")
    }

    @Test func parsesRangeWithUnit() {
        let ingredient = Ingredient(id: "1", text: "2-3 tbsp oil")
        let parsed = ingredient.parseQuantity()
        #expect(parsed.quantity == "2-3 tbsp")
        #expect(parsed.remainder == "oil")
    }

    @Test func parsesCountWithoutUnit() {
        let ingredient = Ingredient(id: "1", text: "3 eggs")
        let parsed = ingredient.parseQuantity()
        #expect(parsed.quantity == "3")
        #expect(parsed.remainder == "eggs")
    }

    @Test func noQuantityReturnsFullTextAsRemainder() {
        let ingredient = Ingredient(id: "1", text: "salt, to taste")
        let parsed = ingredient.parseQuantity()
        #expect(parsed.quantity == "")
        #expect(parsed.remainder == "salt, to taste")
    }
}
