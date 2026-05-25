//
//  IngredientScalerTests.swift
//  SaltyTests
//

import Testing
@testable import Salty

struct IngredientScalerTests {
    
    @Test func parseMixedNumber() {
        #expect(IngredientScaler.parseNumberToken("1 1/2") == 1.5)
    }
    
    @Test func parseFraction() {
        #expect(IngredientScaler.parseNumberToken("3/4") == 0.75)
    }
    
    @Test func parseDecimal() {
        #expect(IngredientScaler.parseNumberToken("2.5") == 2.5)
    }
    
    @Test func scaleHalfCup() {
        let ingredient = Ingredient(id: "1", text: "1 1/2 cups flour")
        let parts = IngredientScaler.displayParts(for: ingredient, scaleFactor: 0.5)
        #expect(parts.quantity == "0.75 cups")
        #expect(parts.remainder == "flour")
    }
    
    @Test func scaleRange() {
        #expect(IngredientScaler.scaleQuantityString("2-3 tbsp oil", factor: 0.5) == "1-1.5 tbsp oil")
    }
    
    @Test func scaleEggs() {
        let ingredient = Ingredient(id: "1", text: "2 eggs")
        let parts = IngredientScaler.displayParts(for: ingredient, scaleFactor: 0.5)
        #expect(parts.quantity == "1")
        #expect(parts.remainder == "eggs")
    }
    
    @Test func unchangedAtFullScale() {
        let ingredient = Ingredient(id: "1", text: "1 1/2 cups flour")
        let parts = IngredientScaler.displayParts(for: ingredient, scaleFactor: 1.0)
        #expect(parts.quantity == "1 1/2 cups")
        #expect(parts.remainder == "flour")
    }
    
    @Test func pinchUnchanged() {
        let ingredient = Ingredient(id: "1", text: "pinch salt")
        let parts = IngredientScaler.displayParts(for: ingredient, scaleFactor: 0.5)
        #expect(parts.quantity == "")
        #expect(parts.remainder == "pinch salt")
    }
    
    @Test func formatScaledAmountTrimsZeros() {
        #expect(IngredientScaler.formatScaledAmount(1.5) == "1.5")
        #expect(IngredientScaler.formatScaledAmount(2.0) == "2")
    }
}
