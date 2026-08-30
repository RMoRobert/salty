//
//  RecipeJunctionInsert.swift
//  SaltyCore
//
//  The one way Salty adds a recipe→category or recipe→tag membership.
//

import Foundation
import GRDB
import SQLiteData

// A junction row's `id` is opaque — a fresh UUIDv7 carrying no relationship to the pair it links (see
// ID-005 in salty-contract/SPEC.md). What keeps a membership from being stored twice is therefore the
// caller: every write path either deletes the recipe's rows before reinserting them, or adds only a
// membership it has computed to be new. These helpers make that second case explicit rather than
// assumed, so the invariant survives a caller that gets its diff wrong.
//
// They also make the `UNIQUE (recipeId, categoryId)` index this schema does not yet have (ID-006) a
// safe addition later. A plain INSERT would start throwing the moment that index existed; SQLite's
// `ON CONFLICT` cannot help, because a conflict target must name an index that already exists, and an
// untargeted `INSERT OR IGNORE` is only reachable here through an API StructuredQueries deprecated
// after 0.24.0. Checking first needs no library support and reads as what it is.
//
// The extra SELECT is per membership on save — a handful of rows behind a user action.

public extension RecipeCategory {

    /// Inserts `row` unless this recipe is already filed under that category. Returns whether a row was
    /// actually inserted, so callers can gate follow-up work (touching `lastModifiedDate`, logging)
    /// without repeating the existence check.
    ///
    /// Matches on the `(recipeId, categoryId)` PAIR, never on `id`: two clients filing the same recipe
    /// under the same category mint different ids, so an id comparison would miss the duplicate that
    /// matters.
    @discardableResult
    static func insertIfAbsent(_ row: RecipeCategory, in db: GRDB.Database) throws -> Bool {
        let alreadyFiled = try RecipeCategory
            .where { $0.recipeId.eq(row.recipeId) && $0.categoryId.eq(row.categoryId) }
            .fetchOne(db) != nil

        guard !alreadyFiled else { return false }
        try RecipeCategory.insert { row }.execute(db)
        return true
    }
}

public extension RecipeTag {

    /// Inserts `row` unless this recipe already carries that tag, returning whether a row was actually
    /// inserted. See `RecipeCategory.insertIfAbsent`.
    @discardableResult
    static func insertIfAbsent(_ row: RecipeTag, in db: GRDB.Database) throws -> Bool {
        let alreadyTagged = try RecipeTag
            .where { $0.recipeId.eq(row.recipeId) && $0.tagId.eq(row.tagId) }
            .fetchOne(db) != nil

        guard !alreadyTagged else { return false }
        try RecipeTag.insert { row }.execute(db)
        return true
    }
}
