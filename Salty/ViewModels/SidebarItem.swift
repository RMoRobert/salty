//
//  SidebarItem.swift
//  Salty
//
//  Created by Robert on 7/18/26.
//

import Foundation

/// A selectable entry in the navigation sidebar.
/// Replaces the previous string-encoded scheme (a `"0"` for for "All Recipes" or prefixes like `"_cat"`, etc. `List(selection:)`
enum SidebarItem: Hashable {
    // Built-in "smart lists" -- predicates over the whole library, not backed by an entity row.
    case allRecipes
    case favorites
    case wantToMake
    // Library entities -- carry the row's UUIDv7 key.
    case category(String)
    case course(String)
    case tag(String)
    // Shopping lists -- swaps the content column from the recipe list to the list-of-lists, whose
    // selection (`selectedShoppingListIDs`) drives the detail column. Mirrors the All Recipes flow.
    case allShoppingLists
}

extension SidebarItem {
    /// The query scope this selection restricts the recipe list to. The smart lists all scope to
    /// `.all` and narrow the results via `forcesFavorites`/`forcesWantToMake` instead.
    var scope: RecipeListScope {
        switch self {
        case .allRecipes, .favorites, .wantToMake: return .all
        case .category(let id): return .category(id)
        case .course(let id): return .course(id)
        case .tag(let id): return .tag(id)
        // Shopping lists don't scope the recipe list at all (the content column shows the lists).
        case .allShoppingLists: return .all
        }
    }

    /// Whether this selection is the shopping-lists column (its own list/detail flow, not recipes).
    var isShoppingLists: Bool { self == .allShoppingLists }

    /// Whether this selection forces the favorites-only filter regardless of the toolbar toggle.
    var forcesFavorites: Bool { self == .favorites }

    /// Whether this selection forces the want-to-make-only filter.
    var forcesWantToMake: Bool { self == .wantToMake }

    /// A stable string key identifying this selection, used in view-refresh identifiers.
    var queryKey: String {
        switch self {
        case .allRecipes:       return "all"
        case .favorites:        return "favorites"
        case .wantToMake:       return "wantToMake"
        case .category(let id): return "cat_\(id)"
        case .course(let id):   return "course_\(id)"
        case .tag(let id):      return "tag_\(id)"
        case .allShoppingLists: return "allShoppingLists"
        }
    }
}
