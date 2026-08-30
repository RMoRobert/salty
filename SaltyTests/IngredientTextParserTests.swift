//
//  IngredientTextParserTests.swift
//  SaltyTests
//

import Testing
@testable import Salty
import SaltyCore

struct IngredientTextParserTests {

    @Test func detectsHeadingAfterBlankLine() {
        let text = "2 cups flour\n\nFrosting:\n1/2 cup sugar"
        let ingredients = IngredientTextParser.parseIngredients(from: text)
        #expect(ingredients.count == 3)
        #expect(ingredients[0].text == "2 cups flour")
        #expect(ingredients[0].isHeading == false)
        #expect(ingredients[1].isHeading == true)
        #expect(ingredients[1].text == "Frosting")
        #expect(ingredients[2].text == "1/2 cup sugar")
    }

    @Test func detectsHeadingEndingWithColon() {
        let text = "Frosting:\n1 cup sugar"
        let ingredients = IngredientTextParser.parseIngredients(from: text)
        #expect(ingredients.count == 2)
        #expect(ingredients[0].isHeading == true)
        #expect(ingredients[0].text == "Frosting")
    }

    @Test func detectsMainIngredientMarker() {
        let ingredients = IngredientTextParser.parseIngredients(from: "2 cups flour [*]")
        #expect(ingredients.count == 1)
        #expect(ingredients[0].isMain == true)
        #expect(ingredients[0].text == "2 cups flour")
    }

    @Test func formatAndParseRoundTripPreservesStructure() {
        let original = "2 cups flour\n\nFrosting:\n1/2 cup sugar"
        let parsed = IngredientTextParser.parseIngredients(from: original)
        let formatted = IngredientTextParser.formatIngredients(parsed)
        let again = IngredientTextParser.parseIngredients(from: formatted)
        #expect(again.count == parsed.count)
        #expect(again.map(\.text) == parsed.map(\.text))
        #expect(again.map(\.isHeading) == parsed.map(\.isHeading))
        #expect(again.map(\.isMain) == parsed.map(\.isMain))
    }

    @Test func cleanUpTextRemovesBulletPrefix() {
        #expect(IngredientTextParser.cleanUpText("* 2 cups flour") == "2 cups flour")
    }
}
