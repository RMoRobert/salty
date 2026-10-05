//
//  RecipeFromTextParserTests.swift
//  SaltyTests
//
//  The rule-based text parser is the import fallback on every device without Smart Parse, and it
//  had no tests: its vocabulary was matched as substrings, so any line containing the letter "g"
//  (the gram unit) was an ingredient, and no title with a "g" in it could ever be the recipe name.
//

import Testing
import Foundation
import SaltyCore

@Suite("RecipeFromTextParser")
struct RecipeFromTextParserTests {
    private let parser = RecipeFromTextParser()

    @Test func titleContainingTheLetterGIsNotMistakenForAnIngredient() {
        let text = """
        Grandma's Lasagna

        Ingredients
        1 lb ground beef
        2 cups ricotta cheese
        250g mozzarella

        Directions
        1. Brown the beef in a large pan.
        2. Layer with the cheeses and bake for 45 minutes.
        """
        let recipe = parser.parseRecipe(from: text)

        #expect(recipe.name == "Grandma's Lasagna")
        #expect(recipe.ingredients.map(\.text) == ["1 lb ground beef", "2 cups ricotta cheese", "250g mozzarella"])
        #expect(recipe.directions.map(\.text) == [
            "Brown the beef in a large pan.",
            "Layer with the cheeses and bake for 45 minutes.",
        ])
    }

    @Test func stepsMentioningGingerAndGarnishAreNotIngredientsWhenThereAreNoHeadings() {
        let text = """
        Ginger Chicken Stir Fry

        2 chicken breasts
        1 tbsp grated ginger

        Heat the oil in a wok and fry the chicken until golden.
        Garnish with sliced ginger and serve.
        """
        let recipe = parser.parseRecipe(from: text)

        #expect(recipe.name == "Ginger Chicken Stir Fry")
        #expect(recipe.ingredients.map(\.text) == ["2 chicken breasts", "1 tbsp grated ginger"])
        #expect(recipe.directions.map(\.text) == [
            "Heat the oil in a wok and fry the chicken until golden.",
            "Garnish with sliced ginger and serve.",
        ])
    }

    @Test func headingsAreShortLinesNotAnyLineMentioningTheWord() {
        let text = """
        Simple Vinaigrette

        INGREDIENTS:
        3 tbsp olive oil
        2 tbsp cooking vinegar

        METHOD
        Mix all the ingredients together until smooth.
        Season to taste.
        """
        let recipe = parser.parseRecipe(from: text)

        #expect(recipe.name == "Simple Vinaigrette")
        #expect(recipe.ingredients.map(\.text) == ["3 tbsp olive oil", "2 tbsp cooking vinegar"],
                "a line mentioning 'cooking' is not the Cooking heading")
        // Unnumbered lines continue the step before them.
        #expect(recipe.directions.map(\.text) == ["Mix all the ingredients together until smooth. Season to taste."],
                "a step mentioning 'ingredients' is not the Ingredients heading")
    }

    @Test func unitsMatchWholeWordsAndVulgarFractions() {
        let text = """
        Ingredients
        ½ cup sugar
        250 g butter
        Salt and pepper to taste
        Egg wash for brushing
        Directions
        1. Beat together.
        """
        let recipe = parser.parseRecipe(from: text)

        #expect(recipe.name == "New Recipe", "nothing after the Ingredients heading is a title")
        #expect(recipe.ingredients.map(\.text) == ["½ cup sugar", "250 g butter", "Salt and pepper to taste", "Egg wash for brushing"])
    }

    @Test func metadataWordsMatchWholeWordsOnly() {
        let text = """
        Jam Tart Base

        Serves 4

        Directions
        1. Spread the preserves over the base.
        2. Bake until it makes a golden crust.
        """
        let recipe = parser.parseRecipe(from: text)

        #expect(recipe.servings == 4)
        #expect(recipe.yield == "", "a step saying 'makes' is not a yield line")
        #expect(recipe.directions.map(\.text) == [
            "Spread the preserves over the base.",
            "Bake until it makes a golden crust.",
        ])
    }

    @Test func emptyAndWindowsLineEndingsAreHandled() {
        let empty = parser.parseRecipe(from: "")
        #expect(empty.name == "New Recipe")
        #expect(empty.ingredients.isEmpty)
        #expect(empty.directions.isEmpty)

        let crlf = "Fluffy Pancakes\r\n\r\nIngredients\r\n1 cup flour\r\n\r\nDirections\r\n1. Mix well.\r\n"
        let recipe = parser.parseRecipe(from: crlf)
        #expect(recipe.name == "Fluffy Pancakes")
        #expect(recipe.ingredients.map(\.text) == ["1 cup flour"])
        #expect(recipe.directions.map(\.text) == ["Mix well."])
    }

    @Test func sectionScansKeepLinesThatMerelyMentionAHeadingWord() {
        let ingredients = parser.parseIngredientLines("""
        Ingredients:
        • 2 tbsp cooking oil
        - 1 jar fruit preserves
        Prep time: 10 min
        """)
        #expect(ingredients.map(\.text) == ["2 tbsp cooking oil", "1 jar fruit preserves"])

        let steps = parser.parseDirectionSteps("""
        Steps
        1. Heat the oil.
        Add the onions and cook until soft.
        2. Stir in the preserves.
        Serves 4
        """)
        #expect(steps.map(\.text) == ["Heat the oil. Add the onions and cook until soft.", "Stir in the preserves."])
    }
}
