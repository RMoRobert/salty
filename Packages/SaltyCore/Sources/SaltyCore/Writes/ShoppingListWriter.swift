//
//  ShoppingListWriter.swift
//  SaltyCore
//
//  The one place a user edit to a shopping list is written, and therefore the one place
//  `lastModifiedDate` is stamped. The companion to `RecipeWriter`.
//
//  `ShoppingList.lastModifiedDate` is nullable (it arrived in SHARED-V0002) and is what sync compares,
//  so a missed bump means an edit that never leaves the device.
//
//  NOT for the sync layer: `syncedRevision` and `syncedSnapshot` are owned entirely by sync, and
//  writes that apply server state carry the server's own `lastModifiedDate`. Those paths keep their
//  own SQL.
//

import Foundation
import GRDB
import SQLiteData

public enum ShoppingListWriter {

    /// Applies `changes` to the stored list and writes it back, stamping `lastModifiedDate` only if
    /// `changes` actually changed something.
    ///
    /// Fetches inside the caller's transaction rather than taking a list the caller holds: a debounced
    /// editor save could otherwise write a stale copy over a newer one from another window. `changes`
    /// receives the stored row, so it can append to the current contents.
    ///
    /// - Parameters:
    ///   - id: the list to edit.
    ///   - db: the transaction to write in.
    ///   - now: the stamp to apply. Injectable for tests; leave it alone in app code.
    ///   - changes: mutates the stored list in place.
    /// - Returns: the list as written, or nil if no list with `id` exists (a list deleted in another
    ///   window while an editor was still open — the write is simply dropped).
    @discardableResult
    public static func update(
        id: String,
        in db: Database,
        now rawNow: Date = Date(),
        _ changes: (inout ShoppingList) throws -> Void
    ) throws -> ShoppingList? {
        // DATE-009, as in `RecipeWriter.save` — see the note there.
        let now = rawNow.roundedToWireMillis
        guard let stored = try ShoppingList.where({ $0.id.eq(id) }).fetchOne(db) else { return nil }

        var edited = stored
        try changes(&edited)

        // Compare with the stamps flattened, so "did anything change?" isn't answered by the stamp
        // itself — and so a caller that set `lastModifiedDate` by hand doesn't defeat the test.
        guard flattened(edited) != flattened(stored) else { return stored }

        // Only ever forwards: a clock that stepped backwards must not make a local edit look older
        // than what the server already holds.
        edited.lastModifiedDate = max(stored.lastModifiedDate ?? .distantPast, now)
        try ShoppingList.update(edited).execute(db)
        return edited
    }

    /// Inserts a new list, stamping it as modified now so sync has something to compare.
    @discardableResult
    public static func insert(_ list: ShoppingList, in db: Database, now rawNow: Date = Date()) throws -> ShoppingList {
        let now = rawNow.roundedToWireMillis   // DATE-009
        var inserting = list
        inserting.lastModifiedDate = max(list.lastModifiedDate ?? .distantPast, now)
        try ShoppingList.insert { inserting }.execute(db)
        return inserting
    }

    /// The list with `lastModifiedDate` flattened, so `==` answers "did the contents change?".
    /// Built from the whole record so a column added later is compared by default.
    private static func flattened(_ list: ShoppingList) -> ShoppingList {
        var copy = list
        copy.lastModifiedDate = nil
        return copy
    }
}
