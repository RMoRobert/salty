//
//  RecipeListSearchOptionsStorage.swift
//  Salty
//
//  Where each search field's on/off state lives in UserDefaults. Read and written only by
//  `RecipeListSettings`; the names predate it, so they stay as they are to keep users' choices.
//

import Foundation
import SaltyCore

extension RecipeListSearchOptions {
    /// UserDefaults key for this search field's enabled state.
    var userDefaultsKey: String {
        switch self {
        case .name: "searchOptionName"
        case .ingredients: "searchOptionIngredients"
        case .mainIngredients: "searchOptionMainIngredients"
        case .introduction: "searchOptionIntroduction"
        case .category: "searchOptionCategory"
        case .course: "searchOptionCourse"
        case .tags: "searchOptionTag"
        case .notes: "searchOptionNotes"
        case .variations: "searchOptionVariations"
        }
    }
}
