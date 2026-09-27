//
//  RecipeLibrarySelectionTests.swift
//  SaltyTests
//
//  Favorites and Want to Make are `.all` narrowed by a filter, not scopes of their own. The last
//  section checks the app's `SidebarItem` agrees with the shared selection it delegates to.
//

import Testing
import Foundation
import SaltyCore
@testable import Salty

struct RecipeLibrarySelectionTests {

    // MARK: - The smart lists

    @Test("the built-in smart lists scope to the whole library and narrow with a filter instead",
          arguments: [RecipeLibrarySelection.allRecipes, .favorites, .wantToMake])
    func smartListsScopeToAll(selection: RecipeLibrarySelection) {
        #expect(selection.scope == .all)
    }

    @Test("only Favorites forces the favorites filter")
    func onlyFavoritesForcesFavorites() {
        #expect(RecipeLibrarySelection.favorites.forcesFavorites)
        #expect(RecipeLibrarySelection.allRecipes.forcesFavorites == false)
        #expect(RecipeLibrarySelection.wantToMake.forcesFavorites == false)
        #expect(RecipeLibrarySelection.category("c").forcesFavorites == false)
    }

    @Test("only Want to Make forces the want-to-make filter")
    func onlyWantToMakeForcesWantToMake() {
        #expect(RecipeLibrarySelection.wantToMake.forcesWantToMake)
        #expect(RecipeLibrarySelection.allRecipes.forcesWantToMake == false)
        #expect(RecipeLibrarySelection.favorites.forcesWantToMake == false)
        #expect(RecipeLibrarySelection.tag("t").forcesWantToMake == false)
    }

    // MARK: - Classifier rows

    @Test("a classifier row scopes to that row and forces no filter")
    func classifierRowsScopeToThemselves() {
        #expect(RecipeLibrarySelection.category("cat-1").scope == .category("cat-1"))
        #expect(RecipeLibrarySelection.course("course-1").scope == .course("course-1"))
        #expect(RecipeLibrarySelection.tag("tag-1").scope == .tag("tag-1"))
    }

    @Test("a selection built from a classifier and id round-trips back to both")
    func classifierRoundTrip() {
        for classifier in LibraryClassifier.allCases {
            let selection = RecipeLibrarySelection(classifier, id: "row-7")
            #expect(selection.classifier == classifier)
            #expect(selection.classifierId == "row-7")
        }
    }

    @Test("the smart lists belong to no classifier")
    func smartListsHaveNoClassifier() {
        for selection in RecipeLibrarySelection.allCases {
            #expect(selection.classifier == nil)
            #expect(selection.classifierId == nil)
        }
    }

    // MARK: - Query keys

    /// Keys feed view-refresh identifiers, so two different selections sharing one would stop a list
    /// from reloading when the sidebar selection changed.
    @Test("query keys are distinct across selections")
    func queryKeysAreDistinct() {
        let keys = [
            RecipeLibrarySelection.allRecipes, .favorites, .wantToMake,
            .category("x"), .course("x"), .tag("x"),
        ].map(\.queryKey)
        #expect(Set(keys).count == keys.count)
    }

    // MARK: - SidebarItem delegates rather than duplicating

    @Test("every recipe-scoping sidebar item maps to the shared selection", arguments: [
        (SidebarItem.allRecipes, RecipeLibrarySelection.allRecipes),
        (.favorites, .favorites),
        (.wantToMake, .wantToMake),
        (.category("cat-1"), .category("cat-1")),
        (.course("course-1"), .course("course-1")),
        (.tag("tag-1"), .tag("tag-1")),
    ])
    func sidebarItemsMapToSelections(item: SidebarItem, expected: RecipeLibrarySelection) {
        #expect(item.librarySelection == expected)
        #expect(item.scope == expected.scope)
        #expect(item.forcesFavorites == expected.forcesFavorites)
        #expect(item.forcesWantToMake == expected.forcesWantToMake)
        #expect(item.queryKey == expected.queryKey)
    }

    /// Shopping lists have no shared selection but must still answer the recipe-list questions safely.
    @Test("the shopping-lists row has no library selection but still answers safely")
    func shoppingListsRowIsNotALibrarySelection() {
        let item = SidebarItem.allShoppingLists
        #expect(item.librarySelection == nil)
        #expect(item.isShoppingLists)
        #expect(item.scope == .all)
        #expect(item.forcesFavorites == false)
        #expect(item.forcesWantToMake == false)
        #expect(item.queryKey == "allShoppingLists")
    }

    @Test("no recipe-scoping sidebar item claims to be the shopping-lists row")
    func onlyShoppingListsRowIsShoppingLists() {
        for item: SidebarItem in [.allRecipes, .favorites, .wantToMake,
                                  .category("c"), .course("c"), .tag("c")] {
            #expect(item.isShoppingLists == false)
        }
    }
}
