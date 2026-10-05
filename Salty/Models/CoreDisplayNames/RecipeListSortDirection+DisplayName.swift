//
//  RecipeListSortDirection+DisplayName.swift
//  Salty
//

import SaltyCore

extension RecipeListSortDirection {
    var displayName: String {
        switch self {
        case .ascending: "Ascending"
        case .descending: "Descending"
        }
    }
}
