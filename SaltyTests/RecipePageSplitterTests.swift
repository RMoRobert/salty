//
//  RecipePageSplitterTests.swift
//  SaltyTests
//
//  Verifies page-boundary grouping and per-group parsing for the multi-recipe PDF import.
//

import Testing
import Foundation
@testable import Salty
import SaltyCore

struct RecipePageSplitterTests {

    @Test func groupsContiguousPagesByStartMarkers() {
        #expect(RecipePageSplitter.groups(pageCount: 3, startPages: []) == [[0, 1, 2]])
        #expect(RecipePageSplitter.groups(pageCount: 3, startPages: [1]) == [[0], [1, 2]])
        #expect(RecipePageSplitter.groups(pageCount: 3, startPages: [1, 2]) == [[0], [1], [2]])
        // Page 0 is always an implicit start, so including it changes nothing.
        #expect(RecipePageSplitter.groups(pageCount: 3, startPages: [0, 1, 2]) == [[0], [1], [2]])
    }

    @Test func groupsHandleEdgeCounts() {
        #expect(RecipePageSplitter.groups(pageCount: 0, startPages: []) == [])
        #expect(RecipePageSplitter.groups(pageCount: 1, startPages: []) == [[0]])
    }

    @Test func splitsPagesIntoSeparateRecipes() {
        let pages = [
            "Chocolate Cake\nFlour\nSugar\nBake until done",
            "Lemon Tart\nLemons\nButter\nMix and chill",
        ]
        // Marking page 2 as a new recipe yields two; no marker merges them into one.
        #expect(RecipePageSplitter.recipes(pageTexts: pages, startPages: [1]).count == 2)
        #expect(RecipePageSplitter.recipes(pageTexts: pages, startPages: []).count == 1)
    }

    @Test func dropsBlankPageGroups() {
        let pages = ["", "Real Recipe\nFlour\nMix well"]
        #expect(RecipePageSplitter.recipes(pageTexts: pages, startPages: [1]).count == 1)
    }
}
