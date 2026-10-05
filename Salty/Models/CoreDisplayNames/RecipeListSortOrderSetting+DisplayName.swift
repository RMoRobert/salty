//
//  RecipeListSortOrderSetting+DisplayName.swift
//  Salty
//
//  The app's names for the recipe list's sort and search choices. SaltyCore defines the choices;
//  each client words them.
//

import SaltyCore

extension RecipeListSortOrderSetting {
    var displayName: String {
        switch self {
        case .byName: "Name"
        case .byDateModified: "Date Modified"
        case .byDateCreated: "Date Created"
        case .bySource: "Source"
        case .byRating: "Rating"
        case .byDifficulty: "Difficulty"
        case .byLastPrepared: "Last Prepared"
        }
    }
}
