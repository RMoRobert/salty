//
//  RecipeClassificationWriter.swift
//  SaltyCore
//
//  Replacing a recipe's categories or tags, and bumping its `lastModifiedDate` when that changed
//  anything: membership travels on the recipe (as `categoryIds`/`tagIds`), so a change that didn't move
//  its clock would never leave this device. The Apple app does the same inline in its category editor.
//

import Foundation
import GRDB

public enum RecipeClassificationWriter {

    /// Makes the recipe's categories exactly `categoryIds` and its tags exactly `tagIds`; nil leaves that
    /// kind alone. Returns whether anything changed.
    ///
    /// Links whose category or tag no longer exists are kept when asked for (the server never cleans
    /// them up, and they're harmless) but never created: a new link to a row that's gone would fail the
    /// foreign key and lose the whole edit. Comparison is by the (recipe, category) pair, never the
    /// link's own id, which every client mints differently.
    @discardableResult
    public static func set(
        categoryIds: [String]?,
        tagIds: [String]?,
        forRecipe recipeId: String,
        in db: Database,
        now: Date = Date()
    ) throws -> Bool {
        var changed = false
        if let categoryIds {
            changed = try replace(recipeId: recipeId, with: categoryIds, junction: "recipeCategory",
                                  column: "categoryId", table: "category", in: db) || changed
        }
        if let tagIds {
            changed = try replace(recipeId: recipeId, with: tagIds, junction: "recipeTag",
                                  column: "tagId", table: "tag", in: db) || changed
        }
        if changed {
            try Recipe.touchLastModified(recipeId: recipeId, in: db, now: now)
        }
        return changed
    }

    /// `junction`, `column` and `table` are the fixed literals above, never caller input.
    private static func replace(
        recipeId: String,
        with ids: [String],
        junction: String,
        column: String,
        table: String,
        in db: Database
    ) throws -> Bool {
        let wanted = Set(ids.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty })
        let current = Set(try String.fetchAll(
            db, sql: #"SELECT "\#(column)" FROM "\#(junction)" WHERE "recipeId" = ?"#, arguments: [recipeId]))

        var changed = false
        for id in current.subtracting(wanted) {
            try db.execute(sql: #"DELETE FROM "\#(junction)" WHERE "recipeId" = ? AND "\#(column)" = ?"#,
                           arguments: [recipeId, id])
            changed = true
        }
        for id in wanted.subtracting(current).sorted() {
            guard try Bool.fetchOne(db, sql: #"SELECT EXISTS (SELECT 1 FROM "\#(table)" WHERE "id" = ?)"#, arguments: [id]) == true
            else { continue }
            try db.execute(sql: #"INSERT INTO "\#(junction)" ("id", "recipeId", "\#(column)") VALUES (?, ?, ?)"#,
                           arguments: [SaltyId.new(), recipeId, id])
            changed = true
        }
        return changed
    }
}
