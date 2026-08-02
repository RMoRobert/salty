//
//  LastSyncedDescription.swift
//  Salty
//
//  Wording for the "Last synced" line in Server settings.
//
//  Relative phrasing is only useful for a few minutes ("3 minutes ago" reads fine, "17 hours ago" makes
//  you do arithmetic), so it switches to a clock time once a sync stops being recent. Pure and injectable
//  (`now`/`calendar`) so the boundaries can be unit-tested without waiting for the clock.
//

import Foundation

enum LastSyncedDescription {
    /// How recent a sync has to be to still be described relative to now, rather than by clock time.
    private static let relativeCutoff: TimeInterval = 6 * 60

    /// Phrase describing when `date` was, e.g. "Just now", "3 minutes ago", "Today at 4:05 PM",
    /// "Yesterday at 11:32 PM", "Jul 12 at 8:15 AM", "Dec 30, 2025 at 8:15 AM".
    static func text(for date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        let elapsed = now.timeIntervalSince(date)

        // A negative interval means the clock moved backwards (time zone change, manual clock edit, a
        // server timestamp from a device that's ahead). Fall through to the absolute form rather than
        // claiming a sync happened in the future.
        if elapsed >= 0 && elapsed < relativeCutoff {
            if elapsed < 15 { return "Just now" }
            if elapsed < 60 { return "Less than a minute ago" }
            let minutes = Int(elapsed / 60)
            return minutes == 1 ? "1 minute ago" : "\(minutes.formatted()) minutes ago"
        }

        // Day comparisons are made against `now`, not the system clock -- `isDateInToday(_:)` and friends
        // would ignore the injected reference date and make this untestable.
        let time = date.formatted(date: .omitted, time: .shortened)
        if calendar.isDate(date, inSameDayAs: now) { return "Today at \(time)" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
           calendar.isDate(date, inSameDayAs: yesterday) {
            return "Yesterday at \(time)"
        }
        if calendar.isDate(date, equalTo: now, toGranularity: .year) {
            return "\(date.formatted(.dateTime.month(.abbreviated).day())) at \(time)"
        }
        return "\(date.formatted(.dateTime.month(.abbreviated).day().year())) at \(time)"
    }

    /// How long until `text(for:)` would produce different wording, so the UI can refresh exactly when the
    /// phrasing goes stale instead of polling. Capped at a minute once the answer stops changing quickly.
    static func refreshInterval(for date: Date, now: Date = Date()) -> TimeInterval {
        let elapsed = now.timeIntervalSince(date)
        guard elapsed >= 0, elapsed < relativeCutoff else { return 60 }
        if elapsed < 15 { return 15 - elapsed }
        if elapsed < 60 { return 60 - elapsed }
        return 60 - elapsed.truncatingRemainder(dividingBy: 60)
    }
}
