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

enum RecipeListSortDirection: String, Codable, CaseIterable {
    case ascending
    case descending
    
    var displayName: String {
        switch self {
        case .ascending:
            return "Ascending"
        case .descending:
            return "Descending"
        }
    }
    
    var sqlSuffix: String {
        switch self {
        case .ascending:
            return "ASC"
        case .descending:
            return "DESC"
        }
    }
}

enum RecipeListSearchOptions: String, Codable, CaseIterable, Hashable {
    case name
    case category
    case course
    case tag
    case introduction
    
    // Compile-time constants for UserDefaults keys (required for @AppStorage)
    static let nameKey = "searchOptionName"
    static let categoryKey = "searchOptionCategory"
    static let courseKey = "searchOptionCourse"
    static let tagKey = "searchOptionTag"
    static let introductionKey = "searchOptionIntroduction"
    
    var displayName: String {
        switch self {
        case .name:
            return "Name"
        case .category:
            return "Category"
        case .course:
            return "Course"
        case .tag:
            return "Tag"
        case .introduction:
            return "Introduction"
        }
    }
    
    /// UserDefaults key for storing this search option's enabled state
    var userDefaultsKey: String {
        switch self {
        case .name:
            return Self.nameKey
        case .category:
            return Self.categoryKey
        case .course:
            return Self.courseKey
        case .tag:
            return Self.tagKey
        case .introduction:
            return Self.introductionKey
        }
    }
}
