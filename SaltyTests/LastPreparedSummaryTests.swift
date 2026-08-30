//
//  LastPreparedSummaryTests.swift
//  SaltyTests
//
//  Covers the heading shown at the top of the "Last Prepared Date" menus, whose interesting behavior is
//  entirely in the multi-selection cases the single-recipe context menu never reaches.
//
//  The heading's four states -- a shared date, mixed dates, never prepared, and nothing selected -- are
//  pinned by what they show and by being distinct from each other, not by their wording, so the labels
//  can be rewritten without touching this file.
//

import Testing
import Foundation
import SaltyCore

struct LastPreparedSummaryTests {

    private func date(_ day: Int) -> Date {
        Calendar.current.date(from: DateComponents(year: 2026, month: 8, day: day, hour: 12))!
    }

    private func text(_ dates: [Date?]) -> String {
        LastPreparedSummary.text(for: dates)
    }

    /// Wrapped rather than inlined: `contains(where:)` is `rethrows`, which `#expect` won't take.
    private func hasADigit(_ text: String) -> Bool {
        text.contains(where: \.isNumber)
    }

    /// How a date reaches the heading, so the assertions don't hard-code a date format either.
    private func formatted(_ date: Date) -> String {
        date.formatted(date: .abbreviated, time: .omitted)
    }

    // MARK: - A date they agree on

    @Test func oneRecipesDateIsShown() {
        #expect(text([date(12)]).contains(formatted(date(12))))
    }

    /// A selection that agrees reports the shared value -- it's a true statement about all of them.
    @Test func aSelectionSharingOneDateShowsThatDate() {
        #expect(text([date(12), date(12), date(12)]).contains(formatted(date(12))))
    }

    /// Equal instants from different Date values still count as agreement.
    @Test func equalInstantsAreNotTreatedAsMixed() {
        let instant = date(12)
        let sameInstant = Date(timeIntervalSinceReferenceDate: instant.timeIntervalSinceReferenceDate)
        #expect(text([instant, sameInstant]) == text([instant]))
    }

    /// A picked day is stored at local noon, so showing a clock time would be showing an artifact.
    @Test func aPickedDayShowsNoClockTime() {
        #expect(!text([date(12)]).contains("12:00"))
        #expect(!text([date(12)]).contains(date(12).formatted(date: .omitted, time: .shortened)))
    }

    // MARK: - Dates they don't agree on

    /// The bug worth guarding: showing one recipe's date over a mixed selection, which reads as a
    /// claim about all of them.
    @Test func aMixedSelectionShowsNoOneRecipesDate() {
        let mixed = text([date(12), date(13)])
        #expect(!mixed.contains(formatted(date(12))))
        #expect(!mixed.contains(formatted(date(13))))
    }

    /// "Some cooked, some never" is mixed too -- the nil is a distinct value, not an absence to ignore.
    @Test func aMixOfSetAndUnsetIsMixedAsWell() {
        let mixed = text([date(12), nil])
        #expect(!mixed.contains(formatted(date(12))))
        #expect(mixed == text([date(12), date(13)]))
    }

    // MARK: - The states are distinct

    @Test func neverPreparedIsItsOwnState() {
        let notSet = text([nil])
        #expect(notSet == text([nil, nil]))
        #expect(notSet != text([date(12)]))
        #expect(notSet != text([date(12), date(13)]))
        // Nothing was prepared, so nothing here should read as a date.
        #expect(!hasADigit(notSet))
    }

    /// Nothing selected gets a bare label rather than a claim -- the menu is disabled in that state.
    @Test func emptySelectionIsDistinctFromNeverPrepared() {
        #expect(text([]) != text([nil]))
        #expect(!hasADigit(text([])))
    }
}
