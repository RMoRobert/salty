//
//  RecipeModelTests.swift
//  SaltyTests
//
//  Pure-Codable tests for the nested value types stored in the recipe's JSON columns.
//  These guard the on-disk JSON shape (the contract the database's `.jsonText` columns
//  persist) without touching the database or the StructuredQueries macros.
//

import Testing
import Foundation
@testable import Salty

struct RecipeModelTests {

    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()

    @Test func directionRoundTrips() throws {
        let original = Direction(id: "d1", isHeading: true, text: "Frosting")
        let decoded = try decoder.decode(Direction.self, from: try encoder.encode(original))
        #expect(decoded == original)
    }

    @Test func ingredientRoundTrips() throws {
        let original = Ingredient(id: "i1", isHeading: false, isMain: true, text: "1 cup flour")
        let decoded = try decoder.decode(Ingredient.self, from: try encoder.encode(original))
        #expect(decoded == original)
    }

    @Test func nutritionRoundTripsWithSparseFields() throws {
        // Only a few fields populated; the rest must survive as nil.
        let original = NutritionInformation(id: "n1", calories: 200, protein: 10, sodium: 150)
        let decoded = try decoder.decode(NutritionInformation.self, from: try encoder.encode(original))
        #expect(decoded == original)
        #expect(decoded.fat == nil)
        #expect(decoded.calcium == nil)
    }

    @Test func arrayOfIngredientsRoundTrips() throws {
        let original = [
            Ingredient(id: "i1", isHeading: true, isMain: false, text: "Dough"),
            Ingredient(id: "i2", isHeading: false, isMain: true, text: "2 cups flour"),
        ]
        let decoded = try decoder.decode([Ingredient].self, from: try encoder.encode(original))
        #expect(decoded == original)
    }

    @Test func decodesDirectionWithMissingOptionalIsHeading() throws {
        // Older exports may omit `isHeading`; it should decode as nil, not fail.
        let json = Data(#"{"id":"d9","text":"Just text"}"#.utf8)
        let decoded = try decoder.decode(Direction.self, from: json)
        #expect(decoded.isHeading == nil)
        #expect(decoded.text == "Just text")
    }

    @Test func difficultyAndRatingEncodeAsRawInts() throws {
        // The recipe table stores these as integers; confirm the raw values are stable.
        #expect(Difficulty.medium.rawValue == 3)
        #expect(Rating.four.rawValue == 4)
        #expect(Difficulty(index: 1) == .easy)
        #expect(Rating(index: 5) == .five)
    }
}
