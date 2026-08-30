//
//  LastSyncedDescriptionTests.swift
//  SaltyTests
//
//  Boundaries of the "Last synced" wording. Pinned to a fixed `now` so the tests never race the clock.
//
//  What's pinned is *where* the description changes form, not what it says at each step: the boundary
//  tests compare two instants against each other rather than against a phrase, so the strings can be
//  rewritten freely. The few checks that do lean on words use the constants below -- reword the
//  description however you like and update those, and the rest of the file keeps working.
//

import Testing
import Foundation
import SaltyCore
@testable import Salty

struct LastSyncedDescriptionTests {
    /// Fixed reference instant: 2026-03-15 14:30:00 UTC. Formatting assertions below avoid clock-time
    /// output (locale-dependent) and check only the shape the app controls.
    private let now = Date(timeIntervalSince1970: 1_773_671_400)

    /// How the relative forms end ("5 minutes ago"), and the unit they count in.
    private let relativeSuffix = "ago"
    private let minuteWord = "minute"

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

    // MARK: - Where the wording changes

    /// Each of these pins a boundary by comparing the instants either side of it: same wording right
    /// up to the cutoff, different wording at it. No phrase appears in the assertion.

    @Test func theOpeningWordingHoldsUntilFifteenSeconds() {
        #expect(text(14.9) == text(0))
        #expect(text(15) != text(14.9))
    }

    @Test func theSubMinuteWordingHoldsUntilOneMinute() {
        #expect(text(59.9) == text(15))
        #expect(text(60) != text(59.9))
    }

    @Test func theMinuteCountHoldsForATwoMinuteBand() {
        #expect(text(119) == text(60))
        #expect(text(120) != text(119))
    }

    @Test func relativeWordingRunsOutAtSixMinutes() {
        #expect(text(5 * 60 + 59) != text(6 * 60))
        #expect(text(5 * 60 + 59).hasSuffix(relativeSuffix))
        #expect(!text(6 * 60).hasSuffix(relativeSuffix))
    }

    // MARK: - What the relative forms count

    @Test func theMinuteCountIsShownAndIsSingularAtOne() {
        #expect(text(60).contains("1 \(minuteWord)"))
        #expect(!text(60).contains("1 \(minuteWord)s"))
        #expect(text(120).contains("2 \(minuteWord)"))
        #expect(text(5 * 60 + 59).contains("5 \(minuteWord)"))
    }

    // MARK: - The absolute forms

    /// Past the relative window it's a clock time, and today, yesterday, and older days each read
    /// differently -- otherwise a week-old sync would look like this morning's.
    @Test func todayYesterdayAndOlderAreAllDistinguished() {
        let today = text(6 * 60)
        let yesterday = text(24 * 60 * 60)
        let older = text(10 * 24 * 60 * 60)

        #expect(today != yesterday)
        #expect(yesterday != older)
        #expect(today != older)
        for result in [today, yesterday, older] {
            #expect(!result.hasSuffix(relativeSuffix))
        }
    }

    /// A sync stamped in the future (clock change, or a device running ahead) must not read as though
    /// it just happened, or produce a negative count -- it falls through to the absolute form.
    @Test func futureDateFallsBackToAbsolute() {
        let result = LastSyncedDescription.text(for: now.addingTimeInterval(120), now: now, calendar: calendar)
        #expect(!result.hasSuffix(relativeSuffix))
        #expect(result != text(0))
        // A negative count would have to render its minus sign somewhere.
        #expect(!result.contains("-"))
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
