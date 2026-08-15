//
//  LibraryItemResolver.swift
//  Salty
//
//  One place for "give me the category/course/tag called X, creating it if it doesn't exist yet".
//
//  The importers each used to do this inline with an exact, case-sensitive `name = ?` lookup, so a
//  file carrying "vegan" or "Breads " next to an existing "Vegan" / "Breads" quietly created a second
//  row -- a duplicate the editors themselves refuse to let you type, since they match with
//  COLLATE NOCASE on the trimmed name. This resolver matches the way the whole app already treats
//  these names: the same normalization `LibraryDuplicateFinder` groups by, so an import can never
//  create a row the Consolidate Duplicates command would immediately want to merge away.
//
//  Raw SQL against a GRDB `Database` (like `LibraryDuplicateMerger`) so it can be driven from the
//  test bundle.
//

import Foundation
import GRDB
import UUIDV7

public enum LibraryItemResolver {

    /// The id of the row named `name`, creating the row if no existing one matches.
    ///
    /// Matching ignores case, surrounding whitespace, and runs of internal whitespace. A name that is
    /// empty once trimmed returns nil -- an unnamed category is not worth creating, and every caller
    /// treats nil as "no classification".
    ///
    /// A newly created row stores the *trimmed* name (its capitalization is kept as given) and gets a
    /// UUIDv7 id, so it sorts by creation time like every other row the app writes -- which is what
    /// the merge's oldest-wins tie-break relies on.
    public static func resolveId(kind: LibraryItemKind, name: String, in db: Database) throws -> String? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        let key = LibraryDuplicateFinder.normalizedName(trimmed)
        let table = tableName(kind)

        // These tables hold tens of rows, so scanning them in Swift costs nothing and keeps the
        // comparison identical to the finder's -- collapsing internal whitespace in SQL would need a
        // custom function, and the two rules drifting apart is exactly the bug this file exists for.
        let existing = try Row.fetchAll(db, sql: #"SELECT "id", IFNULL("name", '') AS "itemName" FROM "\#(table)""#)
        for row in existing {
            let itemName: String = row["itemName"]
            if LibraryDuplicateFinder.normalizedName(itemName) == key {
                let id: String = row["id"]
                return id
            }
        }

        let newId = UUIDV7().uuidString
        try db.execute(
            sql: #"INSERT INTO "\#(table)" ("id", "name", "lastModifiedDate") VALUES (?, ?, ?)"#,
            arguments: [newId, trimmed, Date()]
        )
        return newId
    }

    private static func tableName(_ kind: LibraryItemKind) -> String {
        switch kind {
        case .category: return "category"
        case .course: return "course"
        case .tag: return "tag"
        }
    }
}
