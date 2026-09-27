//
//  RecipeLibrarySelection.swift
//  SaltyCore
//
//  Which slice of the library a navigation selection means, and how that maps onto a recipe-list
//  query. Shared by every client's sidebar, so e.g. "Favorites" (`.all` narrowed by a filter, not a
//  scope of its own) is defined once. Shopping lists are deliberately absent: they are a client
//  navigation concern, not part of "which recipes".
//

import Foundation

/// A selectable slice of the recipe library.
public enum RecipeLibrarySelection: Hashable, Sendable, CaseIterable {
    // Built-in "smart lists" -- predicates over the whole library, not backed by an entity row.
    case allRecipes
    case favorites
    case wantToMake
    // Library entities -- carry the row's UUIDv7 key.
    case category(String)
    case course(String)
    case tag(String)

    /// The three built-in smart lists, in the order a sidebar shows them. `CaseIterable` can't be
    /// synthesised across the associated-value cases, so this is what that conformance provides.
    public static var allCases: [RecipeLibrarySelection] { [.allRecipes, .favorites, .wantToMake] }

    /// The selection for a classifier row.
    public init(_ classifier: LibraryClassifier, id: String) {
        switch classifier {
        case .category: self = .category(id)
        case .course: self = .course(id)
        case .tag: self = .tag(id)
        }
    }
}

extension RecipeLibrarySelection {

    /// The query scope this selection restricts the recipe list to. The smart lists all scope to
    /// `.all` and narrow the results via `forcesFavorites`/`forcesWantToMake` instead.
    public var scope: RecipeListScope {
        switch self {
        case .allRecipes, .favorites, .wantToMake: .all
        case .category(let id): .category(id)
        case .course(let id): .course(id)
        case .tag(let id): .tag(id)
        }
    }

    /// Whether this selection forces the favorites-only filter regardless of the toolbar toggle.
    public var forcesFavorites: Bool { self == .favorites }

    /// Whether this selection forces the want-to-make-only filter.
    public var forcesWantToMake: Bool { self == .wantToMake }

    /// The classifier this selection is a row of, or nil for the built-in smart lists.
    public var classifier: LibraryClassifier? {
        switch self {
        case .allRecipes, .favorites, .wantToMake: nil
        case .category: .category
        case .course: .course
        case .tag: .tag
        }
    }

    /// The id of the classifier row this selection names, or nil for the built-in smart lists.
    public var classifierId: String? {
        switch self {
        case .allRecipes, .favorites, .wantToMake: nil
        case .category(let id), .course(let id), .tag(let id): id
        }
    }

    /// A stable string key identifying this selection, used in view-refresh identifiers.
    public var queryKey: String {
        switch self {
        case .allRecipes:       "all"
        case .favorites:        "favorites"
        case .wantToMake:       "wantToMake"
        case .category(let id): "cat_\(id)"
        case .course(let id):   "course_\(id)"
        case .tag(let id):      "tag_\(id)"
        }
    }
}
