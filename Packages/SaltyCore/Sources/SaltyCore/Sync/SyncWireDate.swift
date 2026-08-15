//
//  SyncWireDate.swift
//  SaltyCore
//
//  The Salty Server wire timestamp format, and the millisecond-resolution comparison that goes with
//  it. Part of the wire contract rather than of any one client, so it lives beside the DTOs.
//

import Foundation

/// Canonical conversion between a `Date` and the Salty Server wire timestamp
/// (`yyyy-MM-dd'T'HH:mm:ss.SSS'Z'` — UTC, millisecond precision). Centralized so the encode and decode
/// paths can never drift: a past drift (`JSONEncoder`'s `.iso8601` strategy dropping fractional seconds)
/// floored uploads to whole seconds while the local copy and the server's echo kept milliseconds, so the
/// reconciler saw local as newer and re-uploaded every recipe on every sync. Pairs with
/// `Date.roundedToWireMillis`, which compares instants at this same millisecond resolution. `internal`
/// (not `private`) so the round-trip can be unit-tested.
public enum SyncWireDate {
    /// Serializes to the wire format the server expects (millisecond fractional seconds, trailing `Z`).
    public static func string(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return formatter.string(from: date)
    }

    /// Parses a server timestamp, tolerating the format variants the server and GRDB are known to emit:
    /// ISO-8601 with then without fractional seconds, a `T`-separated value lacking a timezone, GRDB's
    /// space-separated local format, and a microsecond-precision variant. Order matters — the canonical
    /// `.SSS'Z'` form is tried first.
    public static func date(from string: String) -> Date? {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = iso.date(from: string) { return date }
        iso.formatOptions = [.withInternetDateTime]
        if let date = iso.date(from: string) { return date }

        for format in [
            "yyyy-MM-dd'T'HH:mm:ss",        // no timezone
            "yyyy-MM-dd HH:mm:ss.SSS",      // GRDB default (space-separated)
            "yyyy-MM-dd'T'HH:mm:ss.SSSSSS", // microseconds
        ] {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "en_US_POSIX")
            formatter.timeZone = TimeZone(identifier: "UTC")
            formatter.dateFormat = format
            if let date = formatter.date(from: string) { return date }
        }
        return nil
    }
}

public extension Date {
    /// Rounded to whole milliseconds — the resolution of the sync wire format (`yyyy-MM-dd'T'HH:mm:ss.SSS'Z'`).
    /// The local `Date` (decoded by SQLiteData from `"yyyy-MM-dd HH:mm:ss.SSS"`) and the server `Date`
    /// (decoded by `ISO8601DateFormatter`) can differ by sub-microsecond amounts for the SAME wall-clock
    /// millisecond, so comparing them with `>` / `<` made sync re-upload/re-download everything forever.
    /// Normalizing both sides to whole milliseconds before comparison makes equal instants compare equal.
    public var roundedToWireMillis: Date {
        Date(timeIntervalSinceReferenceDate: (timeIntervalSinceReferenceDate * 1000).rounded() / 1000)
    }
}