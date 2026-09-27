//
//  RecipeItemTextRoundTrip.swift
//  SaltyCore
//
//  Edited ingredient/direction text is parsed back into items only if it actually changed. The
//  parsers mint a fresh UUIDv7 per line, so re-parsing untouched text would change every id: a
//  spurious row to sync and a lost identity. Whole-blob, not per-line: any change re-mints every item.
//

import Foundation

/// Text round-trips for a recipe's ingredient and direction lists.
public enum RecipeItemTextRoundTrip {

    /// The ingredients `text` describes: freshly parsed if it differs from what `current` formats to,
    /// and otherwise `current` unchanged, ids included.
    public static func ingredients(from text: String, current: [Ingredient]) -> [Ingredient] {
        text == IngredientTextParser.formatIngredients(current)
            ? current
            : IngredientTextParser.parseIngredients(from: text)
    }

    /// The directions `text` describes: freshly parsed if it differs from what `current` formats to,
    /// and otherwise `current` unchanged, ids included.
    public static func directions(from text: String, current: [Direction]) -> [Direction] {
        text == DirectionTextParser.formatDirections(current)
            ? current
            : DirectionTextParser.parseDirections(from: text)
    }
}

extension Recipe {

    /// Applies an edited ingredients text to this recipe, keeping the existing items if the text is
    /// unchanged. See `RecipeItemTextRoundTrip`.
    public mutating func applyIngredientsText(_ text: String) {
        ingredients = RecipeItemTextRoundTrip.ingredients(from: text, current: ingredients)
    }

    /// Applies an edited directions text to this recipe, keeping the existing items if the text is
    /// unchanged. See `RecipeItemTextRoundTrip`.
    public mutating func applyDirectionsText(_ text: String) {
        directions = RecipeItemTextRoundTrip.directions(from: text, current: directions)
    }
}
