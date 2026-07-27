//
//  IngredientScaler.swift
//  Salty
//

import Foundation

/// Scales numeric quantities in ingredient lines for temporary recipe display.
enum IngredientScaler {
    
    /// Display split for the ingredients list (quantity bold, remainder regular).
    struct DisplayParts: Equatable {
        var quantity: String
        var remainder: String
        
        var hasQuantity: Bool { !quantity.isEmpty }
    }
    
    /// Returns quantity/remainder for display. At `scaleFactor` 1, preserves original formatting via `parseQuantity()`.
    static func displayParts(for ingredient: Ingredient, scaleFactor: Double) -> DisplayParts {
        guard !ingredient.isHeading else {
            return DisplayParts(quantity: "", remainder: ingredient.text)
        }
        
        if abs(scaleFactor - 1.0) < 0.000_001 {
            let parsed = ingredient.parseQuantity()
            return DisplayParts(quantity: parsed.quantity, remainder: parsed.remainder)
        }
        
        let parsed = ingredient.parseQuantity()
        guard !parsed.quantity.isEmpty,
              let scaledQuantity = scaleQuantityString(parsed.quantity, factor: scaleFactor) else {
            return DisplayParts(quantity: "", remainder: ingredient.text)
        }
        
        return DisplayParts(quantity: scaledQuantity, remainder: parsed.remainder)
    }
    
    /// Full ingredient line with a scaled quantity baked in (e.g. when saving a scaled recipe copy).
    static func scaledText(for ingredient: Ingredient, scaleFactor: Double) -> String {
        let parts = displayParts(for: ingredient, scaleFactor: scaleFactor)
        if parts.hasQuantity {
            if parts.remainder.isEmpty {
                return parts.quantity
            }
            return "\(parts.quantity) \(parts.remainder)"
        }
        return ingredient.text
    }
    
    // MARK: - Quantity scaling
    
    static func scaleQuantityString(_ quantity: String, factor: Double) -> String? {
        let trimmed = quantity.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        
        if let rangeMatch = matchRange(atStartOf: trimmed) {
            guard let low = parseNumberToken(rangeMatch.low),
                  let high = parseNumberToken(rangeMatch.high) else {
                return nil
            }
            let scaledLow = formatScaledAmount(low * factor, preferFraction: prefersFraction(rangeMatch.low))
            let scaledHigh = formatScaledAmount(high * factor, preferFraction: prefersFraction(rangeMatch.high))
            return "\(scaledLow)-\(scaledHigh)\(rangeMatch.suffix)"
        }

        if let singleMatch = matchLeadingNumber(atStartOf: trimmed) {
            guard let value = parseNumberToken(singleMatch.numberToken) else {
                return nil
            }
            return formatScaledAmount(value * factor, preferFraction: prefersFraction(singleMatch.numberToken)) + singleMatch.suffix
        }

        return nil
    }

    /// Fraction-style output suits tokens the author wrote as fractions or whole numbers ("1 1/2", "2");
    /// decimal-authored tokens ("7.5") keep decimal output so metric-style quantities don't turn into
    /// unidiomatic fractions ("3.75 grams", not "3 3/4 grams").
    private static func prefersFraction(_ numberToken: String) -> Bool {
        !numberToken.contains(".")
    }
    
    // MARK: - Number parsing
    
    private struct RangeMatch {
        var low: String
        var high: String
        var suffix: String
    }
    
    private struct SingleNumberMatch {
        var numberToken: String
        var suffix: String
    }
    
    private static let numberTokenPattern = #"\d+(?:\.\d+)?(?:\s+\d+/\d+)?(?:\s*/\s*\d+)?"#
    
    private static func matchRange(atStartOf text: String) -> RangeMatch? {
        let pattern = #"^(?i)(\#(numberTokenPattern))\s*-\s*(\#(numberTokenPattern))(.*)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges >= 4,
              let lowRange = Range(match.range(at: 1), in: text),
              let highRange = Range(match.range(at: 2), in: text),
              let suffixRange = Range(match.range(at: 3), in: text) else {
            return nil
        }
        return RangeMatch(
            low: String(text[lowRange]),
            high: String(text[highRange]),
            suffix: String(text[suffixRange])
        )
    }
    
    private static func matchLeadingNumber(atStartOf text: String) -> SingleNumberMatch? {
        let pattern = #"^(\#(numberTokenPattern))(.*)$"#
        guard let regex = try? NSRegularExpression(pattern: pattern),
              let match = regex.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              match.numberOfRanges >= 3,
              let numberRange = Range(match.range(at: 1), in: text),
              let suffixRange = Range(match.range(at: 2), in: text) else {
            return nil
        }
        return SingleNumberMatch(
            numberToken: String(text[numberRange]),
            suffix: String(text[suffixRange])
        )
    }
    
    static func parseNumberToken(_ token: String) -> Double? {
        let trimmed = token.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return nil }
        
        if trimmed.contains(" ") {
            let parts = trimmed.split(separator: " ", omittingEmptySubsequences: true)
            guard parts.count == 2,
                  let whole = Double(parts[0]),
                  let fraction = parseSimpleFraction(String(parts[1])) else {
                return nil
            }
            return whole + fraction
        }
        
        if trimmed.contains("/") {
            return parseSimpleFraction(trimmed)
        }
        
        return Double(trimmed)
    }
    
    private static func parseSimpleFraction(_ text: String) -> Double? {
        let parts = text.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2,
              let numerator = Double(parts[0].trimmingCharacters(in: .whitespaces)),
              let denominator = Double(parts[1].trimmingCharacters(in: .whitespaces)),
              denominator != 0 else {
            return nil
        }
        return numerator / denominator
    }
    
    static func formatScaledAmount(_ value: Double, preferFraction: Bool = true) -> String {
        guard value.isFinite else { return "0" }
        if abs(value) < 1e-9 { return "0" }

        if preferFraction, let mixed = mixedFractionString(value) {
            return mixed
        }

        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 3
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.3f", value)
    }

    /// Denominators a cook would actually write (halves, thirds, quarters, sixths, eighths),
    /// ascending so the first hit is already in lowest terms (0.75 matches 3/4 before 6/8).
    private static let fractionDenominators = [2, 3, 4, 6, 8]

    /// Renders a value as a "1 1/3"-style mixed fraction when it matches a common cooking fraction
    /// *exactly* -- the tolerance (1e-6) only absorbs Double round-off from parsing/scaling, which is
    /// ~1e-15 (1/3 × 4 = 1.333…). A genuinely inexact amount, even a close decimal approximation
    /// like 0.667 (off from 2/3 by 3e-4), returns nil and keeps its decimal form.
    private static func mixedFractionString(_ value: Double) -> String? {
        guard value > 0 else { return nil }
        let whole = Int(value)
        let frac = value - Double(whole)
        // Whole numbers already render cleanly as decimals ("2"); only step in for a fractional part.
        for den in fractionDenominators {
            let num = (frac * Double(den)).rounded()
            guard num >= 1, num <= Double(den - 1),
                  abs(frac - num / Double(den)) < 0.000_001 else { continue }
            let fracText = "\(Int(num))/\(den)"
            return whole > 0 ? "\(whole) \(fracText)" : fracText
        }
        return nil
    }
}
