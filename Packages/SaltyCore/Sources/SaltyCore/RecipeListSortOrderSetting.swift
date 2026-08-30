//
//  RecipeListSortSetting.swift
//  Salty
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
    case byLastMade

    public var displayName: String {
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
        case .byLastMade:
            return "Last Made"
        }
    }
}

public enum RecipeListSortDirection: String, Codable, CaseIterable {
    case ascending
    case descending
    
    public var displayName: String {
        switch self {
        case .ascending:
            return "Ascending"
        case .descending:
            return "Descending"
        }
    }
    
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

    // Compile-time constants for UserDefaults keys (required for @AppStorage)
    public static let nameKey = "searchOptionName"
    public static let ingredientsKey = "searchOptionIngredients"
    public static let mainIngredientsKey = "searchOptionMainIngredients"
    public static let introductionKey = "searchOptionIntroduction"
    public static let categoryKey = "searchOptionCategory"
    public static let courseKey = "searchOptionCourse"
    public static let tagKey = "searchOptionTag"
    public static let notesKey = "searchOptionNotes"
    public static let variationsKey = "searchOptionVariations"

    public var displayName: String {
        switch self {
        case .name:
            return "Name"
        case .ingredients:
            return "Ingredients"
        case .mainIngredients:
            return "Main Ingredients"
        case .introduction:
            return "Introduction"
        case .category:
            return "Category"
        case .course:
            return "Course"
        case .tags:
            return "Tags"
        case .notes:
            return "Notes"
        case .variations:
            return "Variations"
        }
    }

    /// UserDefaults key for storing this search option's enabled state
    public var userDefaultsKey: String {
        switch self {
        case .name:
            return Self.nameKey
        case .ingredients:
            return Self.ingredientsKey
        case .mainIngredients:
            return Self.mainIngredientsKey
        case .introduction:
            return Self.introductionKey
        case .category:
            return Self.categoryKey
        case .course:
            return Self.courseKey
        case .tags:
            return Self.tagKey
        case .notes:
            return Self.notesKey
        case .variations:
            return Self.variationsKey
        }
    }
}
