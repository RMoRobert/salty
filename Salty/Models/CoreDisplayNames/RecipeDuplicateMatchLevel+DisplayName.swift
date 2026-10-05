//
//  RecipeDuplicateMatchLevel+DisplayName.swift
//  Salty
//

import SaltyCore

extension RecipeDuplicateMatchLevel {
    var displayName: String {
        switch self {
        case .titleAndSource: "Title and Source"
        case .ingredientsAndDirections: "Ingredients and Directions"
        case .allContent: "All Content"
        }
    }

    /// One line describing what this level compares, shown under the list.
    var summaryDescription: String {
        switch self {
        case .titleAndSource: "Matching on title and source"
        case .ingredientsAndDirections: "Matching on title, source, ingredients, and directions"
        case .allContent: "Matching on all recipe content"
        }
    }
}
