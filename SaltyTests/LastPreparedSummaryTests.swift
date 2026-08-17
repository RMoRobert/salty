//
//  LastPreparedSummaryTests.swift
//  SaltyTests
//
//  Covers the heading shown at the top of the "Last Prepared Date" menus, whose interesting behavior is
//  entirely in the multi-selection cases the single-recipe context menu never reaches.
//

import Testing
import Foundation
import SaltyCore

struct LastPreparedSummaryTests {

    private func date(_ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 8, day: day, hour: 12))!
    }

    @Test func neverPreparedReadsAsNotSet() {
        #expect(LastPreparedSummary.text(for: [nil]) == "Last Prepared: Not Set")
    }

    @Test func singleDateIsFormattedWithoutATime() {
        let text = LastPreparedSummary.text(for: [date(12)])
        #expect(text == "Last Prepared: \(date(12).formatted(date: .abbreviated, time: .omitted))")
        // A picked day is stored at local noon, so showing a clock time would be showing an artifact.
        #expect(!text.contains("12:00"))
    }

    /// A selection that agrees reports the shared value — it's a true statement about all of them.
    @Test func selectionSharingOneDateReportsThatDate() {
        #expect(LastPreparedSummary.text(for: [date(12), date(12), date(12)])
                == "Last Prepared: \(date(12).formatted(date: .abbreviated, time: .omitted))")
    }

    @Test func selectionSharingNoDateReportsNotSet() {
        #expect(LastPreparedSummary.text(for: [nil, nil]) == "Last Prepared: Not Set")
    }

    /// Multiple selections shouldn't show date of any single recipe since would misrepresent
    @Test func mixedDatesReportMultiple() {
        #expect(LastPreparedSummary.text(for: [date(12), date(13)]) == "Last Prepared: Multiple Dates")
    }

    /// "Some cooked, some never" is mixed too — the nil is a distinct value, not an absence to ignore.
    @Test func aMixOfSetAndUnsetReportsMultiple() {
        #expect(LastPreparedSummary.text(for: [date(12), nil]) == "Last Prepared: Multiple Dates")
    }

    /// Equal instants from different Date values still count as agreement.
    @Test func equalInstantsAreNotTreatedAsMixed() {
        let instant = date(12)
        let sameInstant = Date(timeIntervalSinceReferenceDate: instant.timeIntervalSinceReferenceDate)
        #expect(LastPreparedSummary.text(for: [instant, sameInstant])
                == "Last Prepared: \(instant.formatted(date: .abbreviated, time: .omitted))")
    }

    /// Nothing selected gets a bare label rather than a claim — the menu is disabled in that state.
    @Test func emptySelectionGetsABareLabel() {
        #expect(LastPreparedSummary.text(for: []) == "Last Prepared")
    }
}
