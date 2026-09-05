//
//  IngredientParseQuantityTests.swift
//  SaltyTests
//

import Testing
@testable import Salty
import SaltyCore

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

    /// Multi-word units are matched longest first. "fluid ounce" listed ahead of "fluid ounces" used
    /// to take the singular out of the plural and leave the "s" on the ingredient: a quantity of
    /// "2 fluid ounce" and a remainder of "s water".
    @Test func parsesPluralMultiWordUnitWhole() {
        let ingredient = Ingredient(id: "1", text: "2 fluid ounces water")
        let parsed = ingredient.parseQuantity()
        #expect(parsed.quantity == "2 fluid ounces")
        #expect(parsed.remainder == "water")
    }

    @Test func parsesSingularMultiWordUnit() {
        let ingredient = Ingredient(id: "1", text: "1 fluid ounce bourbon")
        let parsed = ingredient.parseQuantity()
        #expect(parsed.quantity == "1 fluid ounce")
        #expect(parsed.remainder == "bourbon")
    }

    /// The abbreviated forms, and the unit kept as the author capitalised it.
    @Test(arguments: [
        ("8 fl oz milk", "8 fl oz"),
        ("8 fl. oz. milk", "8 fl. oz."),
        ("8 Fl Oz milk", "8 Fl Oz"),
    ])
    func parsesAbbreviatedFluidOunces(text: String, quantity: String) {
        let parsed = Ingredient(id: "1", text: text).parseQuantity()
        #expect(parsed.quantity == quantity)
        #expect(parsed.remainder == "milk")
    }

    @Test func noQuantityReturnsFullTextAsRemainder() {
        let ingredient = Ingredient(id: "1", text: "salt, to taste")
        let parsed = ingredient.parseQuantity()
        #expect(parsed.quantity == "")
        #expect(parsed.remainder == "salt, to taste")
    }
}
