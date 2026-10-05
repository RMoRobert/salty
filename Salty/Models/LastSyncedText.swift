//
//  LastSyncedText.swift
//  Salty
//
//  The Apple app's wording for the "Last synced" line. SaltyCore decides which phrase fits; this says it.
//

import Foundation
import SaltyCore

extension LastSyncedDescription {
    /// e.g. "Just now", "3 minutes ago", "Today at 4:05 PM", "Yesterday at 11:32 PM", "Jul 12 at 8:15 AM",
    /// "Dec 30, 2025 at 8:15 AM".
    static func text(for date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        phrase(for: date, now: now, calendar: calendar).text
    }
}

extension LastSyncedDescription.Phrase {
    var text: String {
        switch self {
        case .justNow:
            String(localized: "Just now")
        case .underAMinute:
            String(localized: "Less than a minute ago")
        case .minutesAgo(let minutes):
            String(inflected: "^[\(minutes) minute](inflect: true) ago")
        case .today(let date):
            String(localized: "Today at \(date.formatted(date: .omitted, time: .shortened))")
        case .yesterday(let date):
            String(localized: "Yesterday at \(date.formatted(date: .omitted, time: .shortened))")
        case .thisYear(let date):
            String(localized: "\(date.formatted(.dateTime.month(.abbreviated).day())) at \(date.formatted(date: .omitted, time: .shortened))")
        case .earlier(let date):
            String(localized: "\(date.formatted(.dateTime.month(.abbreviated).day().year())) at \(date.formatted(date: .omitted, time: .shortened))")
        }
    }
}
