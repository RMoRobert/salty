//
//  RecipeDuplicateMatchLevel.swift
//  Salty
//
//  How alike two recipes have to be before "Show Duplicate Recipes" reports them together. The
//  levels nest: each one compares everything the looser level does, plus more.
//

import Foundation

enum RecipeDuplicateMatchLevel: String, CaseIterable, Identifiable, Sendable {
    /// Title, source, and source details only -- the loosest useful test, and the one to reach for
    /// when two copies have genuinely drifted (different quantities, a rewritten step).
    case titleAndSource
    /// The above plus the ingredient and direction lines. The default: it survives the differences
    /// copies pick up in normal use (an added note, a re-typed introduction, edited nutrition) while
    /// still insisting the recipe itself is the same.
    case ingredientsAndDirections
    /// Everything: introduction, yield, servings, difficulty, notes, variations, preparation times,
    /// and nutrition as well.
    case allContent

    static let defaultLevel = Self.ingredientsAndDirections

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .titleAndSource: return "Title and Source"
        case .ingredientsAndDirections: return "Ingredients and Directions"
        case .allContent: return "All Content"
        }
    }

    /// One line describing what this level compares, shown under the list.
    var summaryDescription: String {
        switch self {
        case .titleAndSource:
            return "Matching on title and source"
        case .ingredientsAndDirections:
            return "Matching on title, source, ingredients, and directions"
        case .allContent:
            return "Matching on all recipe content"
        }
    }
}
