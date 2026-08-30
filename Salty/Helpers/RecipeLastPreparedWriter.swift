//
//  RecipeLastPreparedWriter.swift
//  Salty
//
//  The single place that stamps a recipe's "last made on" date. Shared by the recipe list's
//  Last Prepared menu and Chef View's "Made It!" button so the column-level rules below stay
//  in one place rather than being re-derived per caller.
//

import Foundation
import SQLiteData

enum RecipeLastPreparedWriter {

    /// Sets (or clears, with `date: nil`) the "last made on" date for one or more recipes.
    ///
    /// Deliberately does not touch `lastModifiedDate`: that would move the recipe to the top of the
    /// "Date Modified" sort every time it's cooked, when the recipe itself didn't change.
    /// `lastModifiedPreparedDate` is stamped instead, and is what sync uses.
    ///
    /// Raw SQL so ONLY these two columns change — a record-level update would rewrite every column,
    /// and the whole point of this write is that `lastModifiedDate` stays exactly as it was.
    static func setLastMade(_ date: Date?, forRecipeIds ids: [String], in database: any DatabaseWriter) async throws {
        guard !ids.isEmpty else { return }
        let stamp = Date()
        try await database.write { db in
            for id in ids {
                try db.execute(
                    sql: """
                        UPDATE recipe
                        SET lastPrepared = ?, lastModifiedPreparedDate = ?
                        WHERE id = ?
                        """,
                    arguments: [date, stamp, id]
                )
            }
        }
    }

    /// Local noon on the calendar day of `day` — the storage form for a user-picked date, chosen so
    /// minor time-zone shifts can't roll the displayed day backwards or forwards. Falls back to the
    /// raw value if the calendar can't build it (it always can for a real date).
    static func localNoon(on day: Date) -> Date {
        Calendar.current.date(bySettingHour: 12, minute: 0, second: 0, of: day) ?? day
    }
}
