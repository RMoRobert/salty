//
//  NutritionValueText.swift
//  SaltyCore
//
//  The text an editor shows for a nutrition amount, and the amount read back from what was typed.
//

import Foundation

/// Converts nutrition amounts to and from the text of an edit field.
///
/// Both directions go through one locale: the field shows "1500" or "1,5" the way the user's region
/// writes numbers, and reads "1,500", "1500" or "1.5" back by that region's rules. The shown text never
/// carries a grouping separator: `Double("1,500")` is nil, and reading fields back that way was silently
/// dropping every amount of a thousand or more on the next save.
public enum NutritionValueText {

    /// `value` as the field should show it: no grouping, at most three decimals, nothing for nil.
    public static func text(for value: Double?, locale: Locale = .current) -> String {
        guard let value, value.isFinite else { return "" }
        return value.formatted(displayStyle(locale))
    }

    /// The amount typed into a field. Nil for an empty field *and* for text that isn't a number; use
    /// `isValid` to tell those apart.
    public static func value(from text: String, locale: Locale = .current) -> Double? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        // The locale parser reads "12 g" as 12 and stops, so anything but digits, separators and a
        // sign is refused outright: a unit typed into the field must show as an error, not round-trip
        // as a number.
        guard trimmed.allSatisfy({ $0.isNumber || Self.numberPunctuation.contains($0) }) else { return nil }
        // Strictly by the locale first, so "1,500" is fifteen hundred in the US and one and a half in
        // Germany; then as a plain "1234.5", which anyone may type without their region's separators.
        // Lenient parsing is deliberately not used: it would read a German "1.5" as fifteen.
        if let parsed = try? Double(trimmed, format: parseStyle(locale), lenient: false), parsed.isFinite {
            return parsed
        }
        if let plain = Double(trimmed), plain.isFinite {
            return plain
        }
        return nil
    }

    /// Whether `text` is empty or reads as a number, so a field can flag what it could not save.
    public static func isValid(_ text: String, locale: Locale = .current) -> Bool {
        text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || value(from: text, locale: locale) != nil
    }

    /// Decimal and grouping separators across locales (period, comma, apostrophes, the spaces Swiss
    /// and French formats use) and a sign.
    private static let numberPunctuation: Set<Character> = [".", ",", "'", "’", " ", "\u{00A0}", "\u{202F}", "-", "+"]

    private static func displayStyle(_ locale: Locale) -> FloatingPointFormatStyle<Double> {
        FloatingPointFormatStyle<Double>(locale: locale)
            .grouping(.never)
            .precision(.fractionLength(0...3))
    }

    /// Grouping is left at the locale's default here, so a typed "1,500" is accepted on the way in even
    /// though it is never produced on the way out.
    private static func parseStyle(_ locale: Locale) -> FloatingPointFormatStyle<Double> {
        FloatingPointFormatStyle<Double>(locale: locale)
    }
}
