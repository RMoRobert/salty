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
            let scaledLow = formatScaledAmount(low * factor)
            let scaledHigh = formatScaledAmount(high * factor)
            return "\(scaledLow)-\(scaledHigh)\(rangeMatch.suffix)"
        }
        
        if let singleMatch = matchLeadingNumber(atStartOf: trimmed) {
            guard let value = parseNumberToken(singleMatch.numberToken) else {
                return nil
            }
            return formatScaledAmount(value * factor) + singleMatch.suffix
        }
        
        return nil
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
    
    static func formatScaledAmount(_ value: Double) -> String {
        guard value.isFinite else { return "0" }
        if abs(value) < 1e-9 { return "0" }
        
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 3
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: NSNumber(value: value)) ?? String(format: "%.3f", value)
    }
}
