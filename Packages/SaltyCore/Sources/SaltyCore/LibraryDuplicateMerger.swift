//
//  LibraryDuplicateMerger.swift
//  Salty
//
//  The database half of the Consolidate Duplicates command: scans `category`/`course`/`tag` for
//  rows sharing a name, and folds each group into one row -- re-pointing every recipe that referenced
//  a duplicate before deleting it, so no recipe loses a classification.
//
//  Written as raw SQL against a GRDB `Database` rather than the StructuredQueries builders so the
//  whole thing can be driven from the test bundle (see the note at the top of DatabaseTests.swift).
//

import Foundation
import GRDB
import OSLog

private let logger = Logger(subsystem: "Salty", category: "Library")

public enum LibraryDuplicateMerger {

    /// What a merge run changed, for the summary shown to the user.
    public struct Summary: Equatable, Sendable {
        public var mergedGroups = 0
        /// Category/course/tag rows deleted (the duplicates, never the survivors).
        public var removedItems = 0
        /// Recipes whose classification was re-pointed -- the ones whose `lastModifiedDate` was bumped.
        public var touchedRecipes = 0

        public var isEmpty: Bool { mergedGroups == 0 }

        public init(mergedGroups: Int = 0, removedItems: Int = 0, touchedRecipes: Int = 0) {
            self.mergedGroups = mergedGroups
            self.removedItems = removedItems
            self.touchedRecipes = touchedRecipes
        }
    }

    // MARK: - Scanning

    /// Every duplicate-name group across all three tables, categories first, then courses, then tags.
    public static func duplicateGroups(
        in db: Database,
        rule: LibraryDuplicateFinder.SurvivorRule = .mostRecipes
    ) throws -> [LibraryDuplicateGroup] {
        try LibraryClassifier.allCases.flatMap { kind in
            LibraryDuplicateFinder.groups(kind: kind, items: try items(kind: kind, in: db), rule: rule)
        }
    }

    /// Scan-and-merge in one transaction, for callers that aren't showing the user a preview first
    /// (the automatic post-sync pass). Uses the device-independent survivor rule so every device
    /// folds a same-named set the same way.
    @discardableResult
    public static func consolidateDuplicates(
        in db: Database,
        rule: LibraryDuplicateFinder.SurvivorRule = .oldestId
    ) throws -> Summary {
        try merge(try duplicateGroups(in: db, rule: rule), in: db)
    }

    /// All rows of one kind with their recipe counts.
    public static func items(kind: LibraryClassifier, in db: Database) throws -> [LibraryClassifierItem] {
        // COUNT(DISTINCT …) so a junction table that already contains a repeated (recipe, item) pair
        // doesn't inflate the count and skew which row is chosen as the survivor.
        let sql: String
        switch kind {
        case .category:
            sql = #"""
                SELECT "id", IFNULL("name", '') AS "itemName",
                       (SELECT COUNT(DISTINCT "recipeId") FROM "recipeCategory" WHERE "categoryId" = "category"."id") AS "recipeCount"
                FROM "category"
                """#
        case .tag:
            sql = #"""
                SELECT "id", IFNULL("name", '') AS "itemName",
                       (SELECT COUNT(DISTINCT "recipeId") FROM "recipeTag" WHERE "tagId" = "tag"."id") AS "recipeCount"
                FROM "tag"
                """#
        case .course:
            sql = #"""
                SELECT "id", IFNULL("name", '') AS "itemName",
                       (SELECT COUNT(*) FROM "recipe" WHERE "courseId" = "course"."id") AS "recipeCount"
                FROM "course"
                """#
        }
        return try Row.fetchAll(db, sql: sql).map { row in
            let id: String = row["id"]
            let name: String = row["itemName"]
            let recipeCount: Int = row["recipeCount"]
            return LibraryClassifierItem(id: id, name: name, recipeCount: recipeCount)
        }
    }

    // MARK: - Merging

    /// Folds each group's duplicates into its survivor. Call inside a single `database.write` so the
    /// whole run is one transaction -- a partially-applied merge would leave recipes pointing at rows
    /// that no longer exist.
    ///
    /// Every recipe that referenced a duplicate gets its `lastModifiedDate` bumped: category and tag
    /// membership sync as `categoryIds`/`tagIds` arrays on the recipe payload, so a junction change
    /// that doesn't move the recipe's timestamp never reaches other devices.
    @discardableResult
    public static func merge(_ groups: [LibraryDuplicateGroup], in db: Database) throws -> Summary {
        var summary = Summary()
        var touchedRecipeIds = Set<String>()

        for group in groups {
            // The groups were captured by an earlier scan; skip any whose survivor has since gone
            // away (another window's editor, a sync, the KMP app) rather than orphaning its recipes.
            guard try rowExists(kind: group.kind, id: group.survivor.id, in: db) else {
                logger.info("Skipping merge for missing \(group.kind.rawValue) \(group.survivor.id)")
                continue
            }
            var mergedAny = false
            for duplicate in group.duplicates where duplicate.id != group.survivor.id {
                guard try rowExists(kind: group.kind, id: duplicate.id, in: db) else { continue }
                let touched = try fold(kind: group.kind, duplicateId: duplicate.id, into: group.survivor.id, in: db)
                touchedRecipeIds.formUnion(touched)
                summary.removedItems += 1
                mergedAny = true
            }
            if mergedAny {
                summary.mergedGroups += 1
            }
        }

        try Recipe.touchLastModified(recipeIds: touchedRecipeIds, in: db)
        summary.touchedRecipes = touchedRecipeIds.count
        return summary
    }

    // MARK: - Private

    private static func tableName(_ kind: LibraryClassifier) -> String {
        switch kind {
        case .category: return "category"
        case .course: return "course"
        case .tag: return "tag"
        }
    }

    private static func rowExists(kind: LibraryClassifier, id: String, in db: Database) throws -> Bool {
        try Int.fetchOne(
            db,
            sql: #"SELECT 1 FROM "\#(tableName(kind))" WHERE "id" = ?"#,
            arguments: [id]
        ) != nil
    }

    /// Moves everything referencing `duplicateId` onto `survivorId`, then deletes the duplicate row.
    /// - Returns: the ids of the recipes that referenced the duplicate.
    private static func fold(
        kind: LibraryClassifier,
        duplicateId: String,
        into survivorId: String,
        in db: Database
    ) throws -> [String] {
        switch kind {
        case .category:
            return try foldJunction(
                junction: "recipeCategory", foreignKey: "categoryId", table: "category",
                duplicateId: duplicateId, into: survivorId, in: db
            )
        case .tag:
            return try foldJunction(
                junction: "recipeTag", foreignKey: "tagId", table: "tag",
                duplicateId: duplicateId, into: survivorId, in: db
            )
        case .course:
            // A recipe has at most one course, so this is a straight re-point -- no de-duplication to
            // do. Re-pointing *before* the delete matters: the FK is ON DELETE SET NULL, so deleting
            // first would silently clear the course from every recipe that used the duplicate.
            let recipeIds = try String.fetchAll(
                db,
                sql: #"SELECT "id" FROM "recipe" WHERE "courseId" = ?"#,
                arguments: [duplicateId]
            )
            try db.execute(
                sql: #"UPDATE "recipe" SET "courseId" = ? WHERE "courseId" = ?"#,
                arguments: [survivorId, duplicateId]
            )
            try db.execute(sql: #"DELETE FROM "course" WHERE "id" = ?"#, arguments: [duplicateId])
            return recipeIds
        }
    }

    /// The junction-table (`recipeCategory` / `recipeTag`) case.
    private static func foldJunction(
        junction: String,
        foreignKey: String,
        table: String,
        duplicateId: String,
        into survivorId: String,
        in db: Database
    ) throws -> [String] {
        let recipeIds = try String.fetchAll(
            db,
            sql: #"SELECT DISTINCT "recipeId" FROM "\#(junction)" WHERE "\#(foreignKey)" = ?"#,
            arguments: [duplicateId]
        )

        // Re-point only where the recipe isn't already linked to the survivor -- there's no unique
        // index on (recipeId, <foreignKey>), so an unguarded UPDATE would leave a recipe listed under
        // the same category twice.
        try db.execute(
            sql: #"""
                UPDATE "\#(junction)" SET "\#(foreignKey)" = ?
                WHERE "\#(foreignKey)" = ?
                  AND "recipeId" NOT IN (SELECT "recipeId" FROM "\#(junction)" WHERE "\#(foreignKey)" = ?)
                """#,
            arguments: [survivorId, duplicateId, survivorId]
        )
        // Whatever is left pointed at the duplicate is a link the recipe already has via the survivor.
        try db.execute(
            sql: #"DELETE FROM "\#(junction)" WHERE "\#(foreignKey)" = ?"#,
            arguments: [duplicateId]
        )
        // Belt and braces for the one case the guard above can't cover: two rows in the *same*
        // duplicate for the same recipe would both have been re-pointed. Scoped to the survivor, so
        // unrelated rows are never touched.
        try db.execute(
            sql: #"""
                DELETE FROM "\#(junction)"
                WHERE "\#(foreignKey)" = ?
                  AND "id" NOT IN (
                      SELECT MIN("id") FROM "\#(junction)" WHERE "\#(foreignKey)" = ? GROUP BY "recipeId"
                  )
                """#,
            arguments: [survivorId, survivorId]
        )
        try db.execute(sql: #"DELETE FROM "\#(table)" WHERE "id" = ?"#, arguments: [duplicateId])

        return recipeIds
    }
}
