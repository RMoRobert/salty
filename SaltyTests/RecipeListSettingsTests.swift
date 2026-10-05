//
//  RecipeListSettingsTests.swift
//  SaltyTests
//
//  The one object behind the Sort By and Search Options menus: what it stores, what it reads back,
//  and the rule that a search always has at least one field to look in.
//

import Testing
import Foundation
@testable import Salty
import SaltyCore

@MainActor
@Suite("RecipeListSettings")
struct RecipeListSettingsTests {

    /// A throwaway defaults domain, emptied before each use.
    private func freshDefaults() throws -> UserDefaults {
        let name = "RecipeListSettingsTests.\(UUID().uuidString)"
        let defaults = try #require(UserDefaults(suiteName: name))
        defaults.removePersistentDomain(forName: name)
        return defaults
    }

    @Test func defaultsAreNameSortAscendingSearchingNames() throws {
        let settings = RecipeListSettings(defaults: try freshDefaults())
        #expect(settings.sortOrder == .byName)
        #expect(settings.sortDirection == .ascending)
        #expect(settings.searchOptions == [.name])
    }

    @Test func changesPersistUnderTheSharedKeys() throws {
        let defaults = try freshDefaults()
        let settings = RecipeListSettings(defaults: defaults)

        settings.sortOrder = .byRating
        settings.sortDirection = .descending
        settings.setSearching(.ingredients, true)

        #expect(defaults.string(forKey: "recipeListSortOrder") == "byRating")
        #expect(defaults.string(forKey: "recipeListSortDirection") == "descending")
        #expect(defaults.bool(forKey: RecipeListSearchOptions.ingredients.userDefaultsKey))

        let reloaded = RecipeListSettings(defaults: defaults)
        #expect(reloaded.sortOrder == .byRating)
        #expect(reloaded.sortDirection == .descending)
        #expect(reloaded.searchOptions == [.name, .ingredients])
    }

    @Test func theLastSearchFieldCannotBeTurnedOff() throws {
        let settings = RecipeListSettings(defaults: try freshDefaults())
        settings.setSearching(.name, false)
        #expect(settings.searchOptions == [.name])

        settings.setSearching(.notes, true)
        settings.setSearching(.name, false)
        #expect(settings.searchOptions == [.notes])
        settings.setSearching(.notes, false)
        #expect(settings.searchOptions == [.notes], "the only remaining field stays on")
    }

    @Test func queryKeyChangesWithAnySetting() throws {
        let settings = RecipeListSettings(defaults: try freshDefaults())
        let initial = settings.queryKey
        settings.setSearching(.tags, true)
        let withTags = settings.queryKey
        #expect(withTags != initial)
        settings.sortDirection = .descending
        #expect(settings.queryKey != withTags)
    }
}
