//
//  RecipeEntityQuery.swift
//  Salty
//
//  How Shortcuts finds recipes: by the id a saved shortcut remembers, by name from the picker's
//  search field, and the list the picker opens on. Reads the library the app opened at launch (an
//  intent that runs without a window still starts the app, and `SaltyApp.init` sets the database up
//  first); the queries themselves are `RecipeEntityLookup`'s.
//

import AppIntents
import SQLiteData

struct RecipeEntityQuery: EntityStringQuery {
    /// Spelled out: inside an App Intents type, a bare `@Dependency` is App Intents' own wrapper.
    @Dependencies.Dependency(\.defaultDatabase) private var database

    func entities(for identifiers: [RecipeEntity.ID]) async throws -> [RecipeEntity] {
        try await database.read { db in
            try RecipeEntityLookup.recipes(ids: identifiers, in: db)
        }
        .map(RecipeEntity.init(recipe:))
    }

    func entities(matching string: String) async throws -> [RecipeEntity] {
        try await database.read { db in
            try RecipeEntityLookup.recipes(matching: string, in: db)
        }
        .map(RecipeEntity.init(recipe:))
    }

    func suggestedEntities() async throws -> [RecipeEntity] {
        try await database.read { db in
            try RecipeEntityLookup.suggestedRecipes(in: db)
        }
        .map(RecipeEntity.init(recipe:))
    }
}
