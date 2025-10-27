//
//  RecipeListSortSetting.swift
//  Salty
//
//  Created by Robert on 10/26/25.
//

import Foundation

enum RecipeListSortOrderSetting: String, Codable, CaseIterable {
    case byName
    case byDateModified
    case byDateCreated
    case bySource
    case byRating
    case byDifficulty
    
    var displayName: String {
        switch self {
        case .byName:
            return "Name"
        case .byDateModified:
            return "Date Modified"
        case .byDateCreated:
            return "Date Created"
        case .bySource:
            return "Source"
        case .byRating:
            return "Rating"
        case .byDifficulty:
            return "Difficulty"
        }
    }
}
