//
//  SchemaOrgDuration.swift
//  SaltyCore
//
//  Purpose: schema.org `Duration` values -- ISO 8601 durations -- as the preparation-time text Salty shows.
//  Rule: salty-contract SPEC.md WEB-028.
//

import Foundation

enum SchemaOrgDuration {

    /// `text` shown as "1 hr 30 min": its total, rounded to the nearest minute (half up), in days, hours
    /// and minutes with zero parts left out. Under a minute is "N sec"; nothing at all is "0 min".
    /// Text that isn't an ISO 8601 duration, or has years or months (no fixed length), comes back as is.
    static func display(_ text: String) -> String {
        guard let seconds = totalSeconds(text.trimmingCharacters(in: .whitespaces)) else {
            return text
        }
        if seconds == 0 {
            return "0 min"
        }
        if seconds < 60 {
            return "\(Int(seconds.rounded(.toNearestOrAwayFromZero))) sec"
        }

        let minutes = Int((seconds / 60).rounded(.toNearestOrAwayFromZero))
        let days = minutes / 1440
        let hours = (minutes % 1440) / 60
        let remainder = minutes % 60

        var parts: [String] = []
        if days > 0 { parts.append(days == 1 ? "1 day" : "\(days) days") }
        if hours > 0 { parts.append("\(hours) hr") }
        if remainder > 0 { parts.append("\(remainder) min") }
        return parts.joined(separator: " ")
    }

    /// `P[nY][nM][nW][nD][T[nH][nM][nS]]`, any number with a `.` or `,` fraction, read case-insensitively.
    /// Nil when the text isn't one, names no component, or has years or months in it.
    private static func totalSeconds(_ text: String) -> Double? {
        let number = #"(\d+(?:[.,]\d+)?)"#
        let pattern = "^P(?:\(number)Y)?(?:\(number)M)?(?:\(number)W)?(?:\(number)D)?"
            + "(?:T(?:\(number)H)?(?:\(number)M)?(?:\(number)S)?)?$"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text))
        else {
            return nil
        }

        func component(_ index: Int) -> Double? {
            guard let range = Range(match.range(at: index), in: text) else { return nil }
            return Double(text[range].replacingOccurrences(of: ",", with: "."))
        }
        let values = (1...7).map(component)

        // "P" alone, or a "T" with no time after it, is not a duration.
        guard values.contains(where: { $0 != nil }) else { return nil }
        if text.uppercased().contains("T"), values[4...6].allSatisfy({ $0 == nil }) { return nil }

        if (values[0] ?? 0) != 0 || (values[1] ?? 0) != 0 { return nil }

        let weeks = values[2] ?? 0, days = values[3] ?? 0
        let hours = values[4] ?? 0, minutes = values[5] ?? 0, seconds = values[6] ?? 0
        return weeks * 604_800 + days * 86_400 + hours * 3_600 + minutes * 60 + seconds
    }
}
