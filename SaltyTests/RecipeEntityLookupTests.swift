//
//  RecipeEntityLookupTests.swift
//  SaltyTests
//
//  What Shortcuts gets back when it asks for recipes: by id in the order asked (skipping any that are
//  gone), by name ignoring case and diacritics, and the picker's opening list -- favorites by name,
//  then the most recently changed -- all capped. And that a recipe entity's private link is the one
//  `salty://recipe/<id>` the app opens.
//

import Testing
import Foundation
import GRDB
import SaltyCore
@testable import Salty

struct RecipeEntityLookupTests {
    private func library(with recipes: [Recipe]) throws -> DatabaseQueue {
        let queue = try makeSyncTestLibrary()
        try queue.write { db in
            for recipe in recipes {
                try RecipeWriter.save(recipe, in: db, now: recipe.lastModifiedDate)
            }
        }
        return queue
    }

    private func recipe(_ id: String, _ name: String, favorite: Bool = false, modified: Date = SyncTestClock.t0) -> Recipe {
        Recipe(id: id, name: name, lastModifiedDate: modified, isFavorite: favorite)
    }

    // MARK: - By id

    @Test func idsComeBackInTheOrderAskedAndMissingOnesAreSkipped() throws {
        let queue = try library(with: [recipe("a", "Apple Pie"), recipe("b", "Bread"), recipe("c", "Chili")])

        let found = try queue.read { try RecipeEntityLookup.recipes(ids: ["c", "gone", "a"], in: $0) }

        #expect(found.map(\.id) == ["c", "a"])
    }

    @Test func noIdsReadNothing() throws {
        let queue = try library(with: [recipe("a", "Apple Pie")])
        #expect(try queue.read { try RecipeEntityLookup.recipes(ids: [], in: $0) }.isEmpty)
    }

    // MARK: - Search

    @Test func searchIgnoresCaseAndDiacriticsAndSortsByName() throws {
        let queue = try library(with: [
            recipe("1", "Crème Brûlée"),
            recipe("2", "Pumpkin Pie"),
            recipe("3", "creme fraiche biscuits"),
        ])

        let found = try queue.read { try RecipeEntityLookup.recipes(matching: "  CREME ", in: $0) }

        #expect(found.map(\.name) == ["Crème Brûlée", "creme fraiche biscuits"])
    }

    @Test func searchMatchesInsideTheName() throws {
        let queue = try library(with: [recipe("1", "Sweet Potato Pie"), recipe("2", "Potatoes Anna"), recipe("3", "Rice")])

        let found = try queue.read { try RecipeEntityLookup.recipes(matching: "potato", in: $0) }

        #expect(found.map(\.id) == ["2", "1"])
    }

    @Test func blankSearchGivesTheSuggestions() throws {
        let queue = try library(with: [recipe("1", "Rice"), recipe("2", "Beans", favorite: true)])

        let searched = try queue.read { try RecipeEntityLookup.recipes(matching: "   ", in: $0) }
        let suggested = try queue.read { try RecipeEntityLookup.suggestedRecipes(in: $0) }

        #expect(searched.map(\.id) == suggested.map(\.id))
        #expect(!searched.isEmpty)
    }

    @Test func searchStopsAtTheLimit() throws {
        let many = (0..<(RecipeEntityLookup.resultLimit + 5)).map { recipe("r\($0)", "Soup \($0)") }
        let queue = try library(with: many)

        let found = try queue.read { try RecipeEntityLookup.recipes(matching: "soup", in: $0) }

        #expect(found.count == RecipeEntityLookup.resultLimit)
    }

    // MARK: - Suggestions

    @Test func suggestionsAreFavoritesByNameThenMostRecentlyChanged() throws {
        let queue = try library(with: [
            recipe("old", "Oatmeal", modified: SyncTestClock.t1),
            recipe("zf", "Ziti", favorite: true, modified: SyncTestClock.t4),
            recipe("new", "Noodles", modified: SyncTestClock.t3),
            recipe("af", "Arepas", favorite: true, modified: SyncTestClock.t0),
            recipe("mid", "Muffins", modified: SyncTestClock.t2),
        ])

        let suggested = try queue.read { try RecipeEntityLookup.suggestedRecipes(in: $0) }

        #expect(suggested.map(\.id) == ["af", "zf", "new", "mid", "old"])
    }

    @Test func suggestionsStopAtTheLimitKeepingTheMostRecent() throws {
        let base = SyncTestClock.t0
        let many = (0..<(RecipeEntityLookup.resultLimit + 5)).map {
            recipe("r\($0)", "Recipe \($0)", modified: base.addingTimeInterval(Double($0) * 60))
        }
        let queue = try library(with: many)

        let suggested = try queue.read { try RecipeEntityLookup.suggestedRecipes(in: $0) }

        #expect(suggested.count == RecipeEntityLookup.resultLimit)
        #expect(suggested.first?.id == "r\(RecipeEntityLookup.resultLimit + 4)")
    }

    // MARK: - Entity

    @Test func entityCarriesThePrivateLinkTheAppOpens() {
        let entity = RecipeEntity(recipe: Recipe(id: "0192a6f0-recipe", name: "Focaccia", isFavorite: true))

        #expect(entity.id == "0192a6f0-recipe")
        #expect(entity.name == "Focaccia")
        #expect(entity.isFavorite)
        #expect(entity.privateLink.absoluteString == "salty://recipe/0192a6f0-recipe")
        #expect(SaltyURL(entity.privateLink) == .recipe(id: "0192a6f0-recipe"))
    }
}
