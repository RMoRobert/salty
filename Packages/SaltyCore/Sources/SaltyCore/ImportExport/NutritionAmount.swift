//
//  NutritionAmount.swift
//  SaltyCore
//
//  Purpose: A schema.org `Energy` or `Mass` value -- "240 calories", "9 g", "1,299.7 mg" -- as a number in
//  the unit Salty stores that nutrition field in. Rule: salty-contract SPEC.md WEB-029, WEB-L03.
//

import Foundation

enum NutritionAmount {

    /// The unit a Salty nutrition field is stored in.
    enum Unit {
        case kilocalories, grams, milligrams, micrograms
    }

    /// `value` in `unit`, or nil when it isn't an amount of that kind.
    ///
    /// Text is `<number> <unit>` with anything after ("9 grams of protein"). A bare number is already in
    /// the field's unit (WEB-L03). A wrong or unknown unit ("12 %") is nil rather than a wrong number.
    static func value(_ value: JSONLDValue, in unit: Unit) -> Double? {
        switch value {
        case .number(let number):
            return number
        case .string(let text):
            return parse(text, in: unit)
        default:
            return nil
        }
    }

    private static func parse(_ text: String, in unit: Unit) -> Double? {
        let pattern = #"^\s*((?:\d{1,3}(?:,\d{3})+|\d+)(?:\.\d+)?|\.\d+)\s*(\S*)"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              let numberRange = Range(match.range(at: 1), in: text),
              let amount = Double(text[numberRange].replacingOccurrences(of: ",", with: ""))
        else {
            return nil
        }

        let written = Range(match.range(at: 2), in: text).map { String(text[$0]) } ?? ""
        let token = written.trimmingCharacters(in: CharacterSet(charactersIn: ".,;:")).lowercased()
        guard !token.isEmpty else {
            return amount
        }
        return convert(amount, from: token, to: unit)
    }

    private static func convert(_ amount: Double, from token: String, to unit: Unit) -> Double? {
        switch unit {
        case .kilocalories:
            switch token {
            case "kcal", "cal", "calorie", "calories", "kilocalorie", "kilocalories":
                return amount
            case "kj", "kilojoule", "kilojoules":
                return rounded(amount / 4.184)
            default:
                return nil
            }
        case .grams, .milligrams, .micrograms:
            guard let grams = grams(amount, token) else { return nil }
            switch unit {
            case .grams: return rounded(grams)
            case .milligrams: return rounded(grams * 1_000)
            default: return rounded(grams * 1_000_000)
            }
        }
    }

    private static func grams(_ amount: Double, _ token: String) -> Double? {
        switch token {
        case "g", "gram", "grams":
            return amount
        case "mg", "milligram", "milligrams":
            return amount / 1_000
        case "mcg", "\u{00B5}g", "\u{03BC}g", "ug", "microgram", "micrograms":
            return amount / 1_000_000
        case "kg", "kilogram", "kilograms":
            return amount * 1_000
        default:
            return nil
        }
    }

    /// Four decimal places: enough for any label, and no `300.00000000000006` mg of sodium from a
    /// conversion's floating-point residue.
    private static func rounded(_ value: Double) -> Double {
        (value * 10_000).rounded() / 10_000
    }
}
