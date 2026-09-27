//
//  SidebarItem.swift
//  Salty
//
//  Created by Robert on 7/18/26.
//

import Foundation
import SaltyCore

/// A selectable entry in the navigation sidebar.
/// Replaces the previous string-encoded scheme (a `"0"` for for "All Recipes" or prefixes like `"_cat"`, etc. `List(selection:)`
///
/// Recipe-scoping cases mirror `SaltyCore.RecipeLibrarySelection`, which owns the query mapping (see
/// `librarySelection`). Kept flat rather than wrapping the shared type because `List(selection:)`
/// binds to it directly at many call sites.
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
    /// The shared library selection this entry means, or nil for the shopping-lists row, which
    /// doesn't scope the recipe list at all.
    var librarySelection: RecipeLibrarySelection? {
        switch self {
        case .allRecipes:       .allRecipes
        case .favorites:        .favorites
        case .wantToMake:       .wantToMake
        case .category(let id): .category(id)
        case .course(let id):   .course(id)
        case .tag(let id):      .tag(id)
        case .allShoppingLists: nil
        }
    }

    /// The query scope this selection restricts the recipe list to. The smart lists all scope to
    /// `.all` and narrow the results via `forcesFavorites`/`forcesWantToMake` instead.
    /// Shopping lists don't scope the recipe list at all (the content column shows the lists).
    var scope: RecipeListScope { librarySelection?.scope ?? .all }

    /// Whether this selection is the shopping-lists column (its own list/detail flow, not recipes).
    var isShoppingLists: Bool { self == .allShoppingLists }

    /// The reorderable sidebar section this selection sits in, or nil for the fixed Library rows. Used to
    /// drop the selection when the section it came from is hidden.
    var sidebarSection: SidebarSection? {
        switch self {
        case .allRecipes, .favorites, .wantToMake: return nil
        case .category: return .categories
        case .course: return .courses
        case .tag: return .tags
        case .allShoppingLists: return .shoppingLists
        }
    }

    /// Whether this selection forces the favorites-only filter regardless of the toolbar toggle.
    var forcesFavorites: Bool { librarySelection?.forcesFavorites ?? false }

    /// Whether this selection forces the want-to-make-only filter.
    var forcesWantToMake: Bool { librarySelection?.forcesWantToMake ?? false }

    /// A stable string key identifying this selection, used in view-refresh identifiers.
    var queryKey: String { librarySelection?.queryKey ?? "allShoppingLists" }
}
