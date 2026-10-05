//
//  RecipeListSearchOptions+DisplayName.swift
//  Salty
//

import SaltyCore

extension RecipeListSearchOptions {
    var displayName: String {
        switch self {
        case .name: "Name"
        case .ingredients: "Ingredients"
        case .mainIngredients: "Main Ingredients"
        case .introduction: "Introduction"
        case .category: "Category"
        case .course: "Course"
        case .tags: "Tags"
        case .notes: "Notes"
        case .variations: "Variations"
        }
    }
}
