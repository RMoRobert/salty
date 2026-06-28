//
//  SyncWireDateTests.swift
//  SaltyTests
//
//  Covers the sync wire-timestamp contract (SyncWireDate) and the millisecond rounding the reconciler
//  relies on (Date.roundedToWireMillis). The regression of record here: when the encode path dropped
//  fractional seconds, the local copy and the server's echo of the same instant compared as "local newer",
//  so sync re-uploaded every recipe forever. These are pure (no database), safe from the test bundle.
//

import Testing
import Foundation
@testable import Salty

struct SyncWireDateTests {

    // MARK: - Encode format

    @Test func encodesCanonicalMillisecondZuluFormat() {
        let date = Date(timeIntervalSince1970: 1_700_000_000.25)
        let string = SyncWireDate.string(from: date)
        // yyyy-MM-dd'T'HH:mm:ss.SSS'Z' — exactly three fractional digits and a trailing Z.
        #expect(string.wholeMatch(of: /\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}\.\d{3}Z/) != nil)
        #expect(string.hasSuffix(".250Z"))
    }

    // MARK: - Round trip

    @Test func roundTripsAMillisecondDate() throws {
        let original = Date(timeIntervalSince1970: 1_700_000_000.25)
        let roundTripped = try #require(SyncWireDate.date(from: SyncWireDate.string(from: original)))
        // Equal to within half a millisecond (the wire resolution).
        #expect(abs(roundTripped.timeIntervalSince(original)) < 0.0005)
    }

    /// The regression guard: a local Date carrying sub-millisecond noise and the server's echo of it
    /// (string → parse) must compare EQUAL through `roundedToWireMillis`, the comparison the reconciler
    /// actually uses. If they didn't, sync would treat local as newer and re-upload on every pass.
    @Test func wireRoundTripIsStableUnderReconcilerComparison() throws {
        let local = Date(timeIntervalSince1970: 1_700_000_000.2503762) // sub-ms drift, as GRDB might decode
        let wire = SyncWireDate.string(from: local)                    // serialized to .250
        let server = try #require(SyncWireDate.date(from: wire))       // server's echo, parsed back

        #expect(local.roundedToWireMillis == server.roundedToWireMillis)
        #expect(!(local.roundedToWireMillis > server.roundedToWireMillis))
    }

    @Test func roundedToWireMillisCollapsesSubMillisecondDifferences() {
        let base = Date(timeIntervalSince1970: 1_700_000_000.250)
        let noisy = Date(timeIntervalSince1970: 1_700_000_000.2501) // +0.1 ms
        #expect(base.roundedToWireMillis == noisy.roundedToWireMillis)
    }

    // MARK: - Decode tolerance

    @Test func decodesKnownServerFormatVariants() {
        #expect(SyncWireDate.date(from: "2025-10-17T21:43:10.250Z") != nil) // canonical
        #expect(SyncWireDate.date(from: "2025-10-17T21:43:10Z") != nil)     // no fractional seconds
        #expect(SyncWireDate.date(from: "2025-10-17T21:43:10") != nil)      // no timezone
        #expect(SyncWireDate.date(from: "2025-10-17 21:43:10.250") != nil)  // GRDB space-separated
        #expect(SyncWireDate.date(from: "not a date") == nil)
        #expect(SyncWireDate.date(from: "") == nil)
    }

    @Test func equivalentRepresentationsParseToTheSameInstant() throws {
        let canonical = try #require(SyncWireDate.date(from: "2025-10-17T21:43:10.000Z"))
        let noFractional = try #require(SyncWireDate.date(from: "2025-10-17T21:43:10Z"))
        let grdbSpaced = try #require(SyncWireDate.date(from: "2025-10-17 21:43:10.000"))
        #expect(canonical == noFractional)
        #expect(canonical == grdbSpaced)
    }
}
