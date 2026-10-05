//
//  LastSyncedDescription.swift
//  SaltyCore
//
//  When the "Last synced" line in Server settings should switch wording. The words are the client's
//  (the Apple app's are in LastSyncedText.swift).
//
//  Relative phrasing is only useful for a few minutes ("3 minutes ago" reads fine, "17 hours ago" makes
//  you do arithmetic), so it switches to a clock time once a sync stops being recent. Pure and injectable
//  (`now`/`calendar`) so the boundaries can be unit-tested without waiting for the clock.
//

import Foundation

public enum LastSyncedDescription {
    /// How recent a sync has to be to still be described relative to now, rather than by clock time.
    private static let relativeCutoff: TimeInterval = 6 * 60

    /// Which wording fits a sync at a given moment. Each client turns it into words.
    public enum Phrase: Equatable, Sendable {
        /// Under 15 seconds ago.
        case justNow
        /// 15 to 59 seconds ago.
        case underAMinute
        /// This many whole minutes ago, up to the relative cutoff.
        case minutesAgo(Int)
        /// Earlier today, by clock time.
        case today(Date)
        /// Yesterday, by clock time.
        case yesterday(Date)
        /// Earlier this year: month, day and time.
        case thisYear(Date)
        /// A previous year (or the future, if the clock moved back): full date and time.
        case earlier(Date)
    }

    /// The wording that fits `date` as seen from `now`.
    public static func phrase(for date: Date, now: Date = Date(), calendar: Calendar = .current) -> Phrase {
        let elapsed = now.timeIntervalSince(date)

        // A negative interval means the clock moved backwards (time zone change, manual clock edit, a
        // server timestamp from a device that's ahead). Fall through to the absolute form rather than
        // claiming a sync happened in the future.
        if elapsed >= 0 && elapsed < relativeCutoff {
            if elapsed < 15 { return .justNow }
            if elapsed < 60 { return .underAMinute }
            return .minutesAgo(Int(elapsed / 60))
        }

        // Day comparisons are made against `now`, not the system clock -- `isDateInToday(_:)` and friends
        // would ignore the injected reference date and make this untestable.
        if calendar.isDate(date, inSameDayAs: now) { return .today(date) }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return .yesterday(date)
        }
        if calendar.isDate(date, equalTo: now, toGranularity: .year) { return .thisYear(date) }
        return .earlier(date)
    }

    /// How long until `phrase(for:)` would produce different wording, so the UI can refresh exactly when the
    /// phrasing goes stale instead of polling. Capped at a minute once the answer stops changing quickly.
    public static func refreshInterval(for date: Date, now: Date = Date()) -> TimeInterval {
        let elapsed = now.timeIntervalSince(date)
        guard elapsed >= 0, elapsed < relativeCutoff else { return 60 }
        if elapsed < 15 { return 15 - elapsed }
        if elapsed < 60 { return 60 - elapsed }
        return 60 - elapsed.truncatingRemainder(dividingBy: 60)
    }
}
