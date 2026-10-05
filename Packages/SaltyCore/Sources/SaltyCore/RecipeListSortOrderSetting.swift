//
//  RecipeListSortOrderSetting.swift
//  SaltyCore
//
//  How the recipe list can be sorted and searched. Each client names the choices itself.
//
//  Created by Robert on 10/26/25.
//

import Foundation

public enum RecipeListSortOrderSetting: String, Codable, CaseIterable {
    case byName
    case byDateModified
    case byDateCreated
    case bySource
    case byRating
    case byDifficulty
    case byLastPrepared
}

public enum RecipeListSortDirection: String, Codable, CaseIterable {
    case ascending
    case descending

    public var sqlSuffix: String {
        switch self {
        case .ascending:
            return "ASC"
        case .descending:
            return "DESC"
        }
    }
}

public enum RecipeListSearchOptions: String, Codable, CaseIterable, Hashable {
    case name
    case ingredients
    /// Narrower sibling of `.ingredients`: only the lines flagged as main ingredients.
    case mainIngredients
    case introduction
    case category
    case course
    case tags
    case notes
    case variations
}
