//
//  LibraryClassifierEditor.swift
//  Salty
//
//  The database half of the category / course / tag editors: create, rename, and delete rows of one
//  classifier, plus the name-conflict lookup the editors use to offer a merge instead of a dead-end
//  "already exists" error.
//
//  Written as raw SQL against a GRDB `Database` rather than the StructuredQueries builders, for the
//  same reason LibraryDuplicateMerger is: it makes the whole thing drivable from the test bundle
//  (see the note at the top of DatabaseTests.swift). LibraryDuplicateMerger performs the merge these
//  conflicts lead to; LibraryClassifierResolver is the importers' create-or-find equivalent.
//

import Foundation
import GRDB
import UUIDV7

public enum LibraryClassifierEditor {

    /// An existing row whose name collides with one the user just typed.
    public struct NameConflict: Hashable, Sendable {
        public let id: String
        /// The stored name, which may differ from what was typed in case or spacing.
        public let name: String

        public init(id: String, name: String) {
            self.id = id
            self.name = name
        }
    }

    // MARK: - Lookup

    /// The existing row of `classifier` whose name matches `name`, or nil if the name is free.
    ///
    /// Matching uses `LibraryDuplicateFinder`'s normalization -- case-insensitive, ignoring
    /// surrounding whitespace and collapsing internal runs -- so the editor refuses to create exactly
    /// the pairs the Consolidate Duplicates command would later offer to merge.
    ///
    /// - Parameter excludingId: the row being renamed, so a name that only changes capitalization
    ///   ("desserts" → "Desserts") isn't reported as a conflict with itself.
    public static func existingRow(
        classifier: LibraryClassifier,
        name: String,
        excludingId: String? = nil,
        in db: Database
    ) throws -> NameConflict? {
        let key = LibraryDuplicateFinder.normalizedName(name)
        guard !key.isEmpty else { return nil }

        // These tables hold tens of rows, so scanning them in Swift costs nothing and keeps the
        // comparison identical to the finder's -- collapsing internal whitespace in SQL would need a
        // custom function, and the two rules drifting apart is exactly the bug this guards against.
        let rows = try Row.fetchAll(
            db,
            sql: #"SELECT "id", IFNULL("name", '') AS "itemName" FROM "\#(classifier.tableName)""#
        )
        for row in rows {
            let id: String = row["id"]
            guard id != excludingId else { continue }
            let name: String = row["itemName"]
            if LibraryDuplicateFinder.normalizedName(name) == key {
                return NameConflict(id: id, name: name)
            }
        }
        return nil
    }

    // MARK: - Mutation

    /// Inserts a row and returns its id. The name is stored trimmed, keeping the capitalization given.
    ///
    /// Ids are UUIDv7 so a new row sorts by creation time like every other row the app writes -- which
    /// is what the merge's oldest-wins tie-break relies on.
    @discardableResult
    public static func create(
        classifier: LibraryClassifier,
        name: String,
        in db: Database
    ) throws -> String {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let id = UUIDV7().uuidString
        try db.execute(
            sql: #"INSERT INTO "\#(classifier.tableName)" ("id", "name", "lastModifiedDate") VALUES (?, ?, ?)"#,
            arguments: [id, trimmed, Date()]
        )
        return id
    }

    /// Renames a row, bumping `lastModifiedDate` so the change syncs.
    ///
    /// Recipes aren't touched: category and tag membership syncs as id arrays and a course as an id,
    /// so a renamed row reaches other devices on its own row, not through the recipes using it.
    public static func rename(
        classifier: LibraryClassifier,
        id: String,
        to name: String,
        in db: Database
    ) throws {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        try db.execute(
            sql: #"UPDATE "\#(classifier.tableName)" SET "name" = ?, "lastModifiedDate" = ? WHERE "id" = ?"#,
            arguments: [trimmed, Date(), id]
        )
    }

    /// Deletes rows and returns the ids of the recipes that referenced them.
    ///
    /// Those recipes get their `lastModifiedDate` bumped: membership syncs as `categoryIds`/`tagIds`
    /// arrays on the recipe payload (and `courseId` for a course), so a classification that vanishes
    /// without moving the recipe's timestamp would never reach another device.
    @discardableResult
    public static func delete(
        classifier: LibraryClassifier,
        ids: some Sequence<String>,
        in db: Database
    ) throws -> Set<String> {
        var touchedRecipeIds = Set<String>()

        for id in ids {
            switch classifier {
            case .category:
                touchedRecipeIds.formUnion(
                    try deleteJunctioned(junction: "recipeCategory", foreignKey: "categoryId", classifier: classifier, id: id, in: db)
                )
            case .tag:
                touchedRecipeIds.formUnion(
                    try deleteJunctioned(junction: "recipeTag", foreignKey: "tagId", classifier: classifier, id: id, in: db)
                )
            case .course:
                // recipe.courseId is ON DELETE SET NULL, so the recipes are cleared by the delete
                // itself -- collect them first, then let the FK do the work. Rewriting whole recipe
                // rows here would re-write every column, which Recipe.touchLastModified exists to avoid.
                let recipeIds = try String.fetchAll(
                    db,
                    sql: #"SELECT "id" FROM "recipe" WHERE "courseId" = ?"#,
                    arguments: [id]
                )
                try db.execute(sql: #"DELETE FROM "course" WHERE "id" = ?"#, arguments: [id])
                touchedRecipeIds.formUnion(recipeIds)
            }
        }

        try Recipe.touchLastModified(recipeIds: touchedRecipeIds, in: db)
        return touchedRecipeIds
    }

    /// The junction-table (`recipeCategory` / `recipeTag`) case: drop the links, then the row.
    private static func deleteJunctioned(
        junction: String,
        foreignKey: String,
        classifier: LibraryClassifier,
        id: String,
        in db: Database
    ) throws -> [String] {
        let recipeIds = try String.fetchAll(
            db,
            sql: #"SELECT DISTINCT "recipeId" FROM "\#(junction)" WHERE "\#(foreignKey)" = ?"#,
            arguments: [id]
        )
        try db.execute(sql: #"DELETE FROM "\#(junction)" WHERE "\#(foreignKey)" = ?"#, arguments: [id])
        try db.execute(sql: #"DELETE FROM "\#(classifier.tableName)" WHERE "id" = ?"#, arguments: [id])
        return recipeIds
    }
}
