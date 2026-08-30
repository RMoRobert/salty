//
//  LastPreparedSummary.swift
//  Salty
//  Created by Robert, 8/16/26
//
//  Wording for the read-only heading at the top of the "Last Prepared Date" menus.
//
//  Formats a "last prepared" date for a recipe to match the Get Info format (abbreviated date,
//  no time -- a day picked from calendar is stored as local noon, no exact time, and day-of sets
//  are stored as current time but still displayed as date only).
//
//  Pure, so the multi-selection rules below are unit-testable without a database or a menu.
//

import Foundation

public enum LastPreparedSummary {

    /// Heading for a menu acting on recipes whose `lastPrepared` values are `dates`.
    ///
    /// A multiple-select says so rather than picking any one recipe's date to display.
    /// An empty selection gets a bare label: there's nothing to report, and menu items that act on a
    /// selection are disabled in that state anyway.
    public static func text(for dates: [Date?]) -> String {
        guard !dates.isEmpty else { return "Last Prepared" }

        // Compare by instant, not by Date identity, so equal timestamps from different sources match.
        let distinct = Set(dates.map { $0?.timeIntervalSinceReferenceDate })
        guard distinct.count == 1, let value = dates.first else { return "Last Prepared: Multiple Dates" }
        guard let value else { return "Last Prepared: Not Set" }
        return "Last Prepared: \(value.formatted(date: .abbreviated, time: .omitted))"
    }
}
