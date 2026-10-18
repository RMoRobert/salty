//
//  RecipeEntityLookup.swift
//  Salty
//
//  The library reads behind `RecipeEntityQuery`: the recipes Shortcuts asks for by id, the ones it
//  offers in its recipe picker, and the ones matching what is typed into that picker's search field.
//  Plain functions over a `Database`, so the tests run them against an in-memory library.
//

import Foundation
import GRDB
import SQLiteData
import SaltyCore

enum RecipeEntityLookup {
    /// The most recipes a search or the suggestion list returns. Each one carries its thumbnail into
    /// Shortcuts, so this is kept to a list someone would scroll; typing narrows it from there.
    static let resultLimit = 50

    /// The recipes with these ids, in the order asked for. Ids not in the library (deleted, or not yet
    /// synced here) are left out rather than failing the whole request.
    static func recipes(ids: [String], in db: Database) throws -> [Recipe] {
        guard !ids.isEmpty else { return [] }
        let found = try Recipe.where { $0.id.in(ids) }.fetchAll(db)
        let byId = Dictionary(found.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return ids.compactMap { byId[$0] }
    }

    /// Recipes whose name contains `text`, ignoring case and diacritics as system search fields do
    /// ("creme" finds "Crème Brûlée"), sorted by name. Blank text gives the suggestions instead.
    static func recipes(matching text: String, in db: Database) throws -> [Recipe] {
        let query = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return try suggestedRecipes(in: db) }

        let ids = try idsAndNames(favoritesOnly: false, in: db)
            .filter { $0.name.localizedStandardContains(query) }
            .sorted(using: KeyPathComparator(\.name, comparator: .localizedStandard))
            .prefix(resultLimit)
            .map(\.id)
        return try recipes(ids: ids, in: db)
    }

    /// What the recipe picker lists before anything is typed: favorites by name, then the rest by most
    /// recently changed, up to `resultLimit` in all.
    static func suggestedRecipes(in db: Database) throws -> [Recipe] {
        let favoriteIds = try idsAndNames(favoritesOnly: true, in: db)
            .sorted(using: KeyPathComparator(\.name, comparator: .localizedStandard))
            .prefix(resultLimit)
            .map(\.id)

        let remaining = resultLimit - favoriteIds.count
        let recentIds = remaining > 0
            ? try Recipe.where { !$0.isFavorite }
                .order { $0.lastModifiedDate.desc() }
                .limit(remaining)
                .select { $0.id }
                .fetchAll(db)
            : []

        return try recipes(ids: favoriteIds + recentIds, in: db)
    }

    /// One recipe's id and name, all that matching and sorting need.
    private struct NamedID {
        let id: String
        let name: String
    }

    /// Every recipe's (or every favorite's) id and name, without loading bodies or photos. Plain SQL:
    /// the query builder's two-column `select` won't resolve on `Recipe`, which is a GRDB
    /// `TableRecord` too.
    private static func idsAndNames(favoritesOnly: Bool, in db: Database) throws -> [NamedID] {
        let sql = favoritesOnly
            ? "SELECT id, name FROM recipe WHERE isFavorite"
            : "SELECT id, name FROM recipe"
        return try Row.fetchAll(db, sql: sql).map { NamedID(id: $0["id"], name: $0["name"]) }
    }
}
