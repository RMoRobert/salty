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
        #expect(parts.quantity == "3/4 cups")
        #expect(parts.remainder == "flour")
    }

    @Test func scaleRange() {
        #expect(IngredientScaler.scaleQuantityString("2-3 tbsp oil", factor: 0.5) == "1-1 1/2 tbsp oil")
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
        #expect(IngredientScaler.formatScaledAmount(1.5, preferFraction: false) == "1.5")
        #expect(IngredientScaler.formatScaledAmount(2.0) == "2")
    }

    // MARK: - Mixed-fraction display for exact amounts

    @Test func exactAmountsDisplayAsMixedFractions() {
        #expect(IngredientScaler.formatScaledAmount(1.5) == "1 1/2")
        #expect(IngredientScaler.formatScaledAmount(0.75) == "3/4")
        #expect(IngredientScaler.formatScaledAmount(0.125) == "1/8")
        #expect(IngredientScaler.formatScaledAmount(1.0 / 3.0 * 4.0) == "1 1/3")  // Double round-off absorbed
        #expect(IngredientScaler.formatScaledAmount(5.0 / 8.0) == "5/8")
    }

    @Test func inexactAmountsKeepDecimalForm() {
        #expect(IngredientScaler.formatScaledAmount(1.334) == "1.334")
        #expect(IngredientScaler.formatScaledAmount(0.35) == "0.35")
        #expect(IngredientScaler.formatScaledAmount(0.667) == "0.667")
    }

    @Test func scalingFractionInputYieldsMixedFraction() {
        let ingredient = Ingredient(id: "1", text: "1/3 cup sugar")
        let parts = IngredientScaler.displayParts(for: ingredient, scaleFactor: 4.0)
        #expect(parts.quantity == "1 1/3 cup")
        #expect(parts.remainder == "sugar")
    }

    /// Decimal-authored quantities stay decimal even when the result is an exact fraction,
    /// so metric-style amounts don't turn into unidiomatic fractions ("3.75 grams", not "3 3/4 grams").
    @Test func decimalAuthoredQuantityStaysDecimal() {
        #expect(IngredientScaler.scaleQuantityString("7.5 grams yeast", factor: 0.5) == "3.75 grams yeast")
        #expect(IngredientScaler.scaleQuantityString("2.5 cups flour", factor: 0.5) == "1.25 cups flour")
    }

    /// A saved scaled copy must re-parse: "1 1/3" is a mixed-number token the parser understands.
    @Test func mixedFractionOutputRoundTripsThroughParser() {
        #expect(IngredientScaler.parseNumberToken("1 1/3") == 1.0 + 1.0 / 3.0)
    }
}
