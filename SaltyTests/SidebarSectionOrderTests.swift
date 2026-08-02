//
//  SidebarSectionOrderTests.swift
//  SaltyTests
//
//  Order storage and the "at least one of Categories, Courses, or Tags" rule for the sidebar sections.
//  Visibility tests run against their own UserDefaults suite so they never touch the real preferences.
//

import Testing
import Foundation
@testable import Salty

struct SidebarSectionOrderTests {

    // MARK: - Order encoding

    @Test func emptyStorageDecodesToDefaultOrder() {
        #expect(SidebarSectionOrder.decode("") == SidebarSectionOrder.defaultOrder)
    }

    @Test func roundTripsAReorderedList() {
        let order: [SidebarSection] = [.shoppingLists, .tags, .categories, .courses]
        #expect(SidebarSectionOrder.decode(SidebarSectionOrder.encode(order)) == order)
    }

    @Test func dropsUnknownAndDuplicateEntries() {
        // "smartLists" stands in for a section written by a future version and since removed.
        let decoded = SidebarSectionOrder.decode("tags,smartLists,tags,categories")
        #expect(decoded == [.tags, .categories, .courses, .shoppingLists])
    }

    @Test func appendsSectionsMissingFromStoredValue() {
        // What a stored order from a build that predates Shopping Lists would look like.
        let decoded = SidebarSectionOrder.decode("courses,categories,tags")
        #expect(decoded == [.courses, .categories, .tags, .shoppingLists])
    }

    // MARK: - Moving

    @Test func movesUpAndDownOneStep() {
        let order = SidebarSectionOrder.defaultOrder  // categories, courses, tags, shoppingLists
        #expect(SidebarSectionOrder.moved(order, .tags, by: -1) == [.categories, .tags, .courses, .shoppingLists])
        #expect(SidebarSectionOrder.moved(order, .courses, by: 1) == [.categories, .tags, .courses, .shoppingLists])
    }

    @Test func movesPastEitherEndAreNoOps() {
        let order = SidebarSectionOrder.defaultOrder
        #expect(SidebarSectionOrder.moved(order, .categories, by: -1) == order)
        #expect(SidebarSectionOrder.moved(order, .shoppingLists, by: 1) == order)
    }

    @Test func dragReorderMovesTheDraggedRow() {
        let order = SidebarSectionOrder.defaultOrder
        let moved = SidebarSectionOrder.moved(order, fromOffsets: IndexSet(integer: 3), toOffset: 0)
        #expect(moved == [.shoppingLists, .categories, .courses, .tags])
    }

    // MARK: - Visibility rule

    // Deliberately no UserDefaults here: a per-test suite leaves a plist behind in the test host's
    // container, and enough of those accumulating stops the host from launching. The rule takes its
    // visibility lookup as a closure precisely so it can be checked in memory.
    private func canHide(_ section: SidebarSection, visible: Set<SidebarSection>) -> Bool {
        SidebarSectionOrder.canHide(section) { visible.contains($0) }
    }

    @Test func anySectionCanBeHiddenWhileTheOthersAreShown() {
        for section in SidebarSection.allCases {
            #expect(canHide(section, visible: Set(SidebarSection.allCases)))
        }
    }

    @Test func keepsTheLastOfCategoriesCoursesAndTagsVisible() {
        #expect(!canHide(.tags, visible: [.tags, .shoppingLists]))
        #expect(!canHide(.categories, visible: [.categories]))
        // Showing another of the three frees the last one to be hidden.
        #expect(canHide(.tags, visible: [.tags, .courses]))
    }

    @Test func shoppingListsCanAlwaysBeHidden() {
        #expect(canHide(.shoppingLists, visible: [.shoppingLists]))
        #expect(canHide(.shoppingLists, visible: [.tags, .shoppingLists]))
    }

    // MARK: - Selection fallback

    @Test func sidebarItemsMapToTheirSection() {
        #expect(SidebarItem.category("abc").sidebarSection == .categories)
        #expect(SidebarItem.course("abc").sidebarSection == .courses)
        #expect(SidebarItem.tag("abc").sidebarSection == .tags)
        #expect(SidebarItem.allShoppingLists.sidebarSection == .shoppingLists)
        #expect(SidebarItem.allRecipes.sidebarSection == nil)
        #expect(SidebarItem.favorites.sidebarSection == nil)
        #expect(SidebarItem.wantToMake.sidebarSection == nil)
    }
}
