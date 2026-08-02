//
//  LastSyncedDescriptionTests.swift
//  SaltyTests
//
//  Boundaries of the "Last synced" wording. Pinned to a fixed `now` so the tests never race the clock.
//

import Testing
import Foundation
@testable import Salty

struct LastSyncedDescriptionTests {
    /// Fixed reference instant: 2026-03-15 14:30:00 UTC. Formatting assertions below avoid clock-time
    /// output (locale-dependent) and check only the prefix the app controls.
    private let now = Date(timeIntervalSince1970: 1_773_671_400)

    /// Fixed to UTC so day-boundary assertions don't depend on where the test machine is.
    private var calendar: Calendar {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        return calendar
    }

    private func ago(_ seconds: TimeInterval) -> Date { now.addingTimeInterval(-seconds) }

    private func text(_ seconds: TimeInterval) -> String {
        LastSyncedDescription.text(for: ago(seconds), now: now, calendar: calendar)
    }

    // MARK: - Relative window

    @Test func justNowUnderFifteenSeconds() {
        #expect(text(0) == "Just now")
        #expect(text(14.9) == "Just now")
    }

    @Test func lessThanAMinuteFromFifteenSeconds() {
        #expect(text(15) == "Less than a minute ago")
        #expect(text(59.9) == "Less than a minute ago")
    }

    @Test func singularMinuteIsNotPluralized() {
        #expect(text(60) == "1 minute ago")
        #expect(text(119) == "1 minute ago")
    }

    @Test func minutesUpToTheCutoff() {
        #expect(text(120) == "2 minutes ago")
        #expect(text(5 * 60) == "5 minutes ago")
        #expect(text(5 * 60 + 59) == "5 minutes ago")
    }

    // MARK: - Absolute window

    @Test func switchesToClockTimeAtSixMinutes() {
        let result = text(6 * 60)
        #expect(!result.hasSuffix("ago"))
        #expect(result.hasPrefix("Today at "))
    }

    @Test func yesterdayIsNamed() {
        #expect(text(24 * 60 * 60).hasPrefix("Yesterday at "))
    }

    @Test func olderDatesUseMonthAndDay() {
        let result = text(10 * 24 * 60 * 60)
        #expect(result.contains(" at "))
        #expect(!result.hasPrefix("Today"))
        #expect(!result.hasPrefix("Yesterday"))
    }

    /// A sync stamped in the future (clock change, or a device whose clock runs ahead) must not read as
    /// "Just now" or produce a negative count -- it falls through to the absolute form.
    @Test func futureDateFallsBackToAbsolute() {
        let result = LastSyncedDescription.text(for: now.addingTimeInterval(120), now: now, calendar: calendar)
        #expect(!result.hasSuffix("ago"))
        #expect(result.hasPrefix("Today at "))
    }

    // MARK: - Refresh scheduling

    @Test func refreshIntervalIsAlwaysPositive() {
        for seconds in [0.0, 1, 14.99, 15, 59.99, 60, 61, 299, 359.99, 360, 4000] {
            let interval = LastSyncedDescription.refreshInterval(for: ago(seconds), now: now)
            #expect(interval > 0, "non-positive interval at \(seconds)s would spin the refresh loop")
            #expect(interval <= 60)
        }
    }

    @Test func refreshIntervalTargetsTheNextWordingChange() {
        #expect(LastSyncedDescription.refreshInterval(for: ago(0), now: now) == 15)
        #expect(LastSyncedDescription.refreshInterval(for: ago(20), now: now) == 40)
        #expect(LastSyncedDescription.refreshInterval(for: ago(90), now: now) == 30)
    }
}
