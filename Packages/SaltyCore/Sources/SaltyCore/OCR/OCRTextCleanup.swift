//
//  OCRTextCleanup.swift
//  SaltyCore
//
//  Fixes OCR character confusions that language correction misses ("Ib" for "lb", "0z" for "oz",
//  "l/2" for "1/2"). Each rule is anchored to a quantity or unit so ordinary prose is left alone.
//

import Foundation

public enum OCRTextCleanup {
    public static func apply(to text: String) -> String {
        var cleaned = text
        // "2 Ibs" -> "2 lbs", "1 Ib" -> "1 lb"
        cleaned = cleaned.replacing(/(\d\s?)Ib(s?)\b/) { "\($0.1)lb\($0.2)" }
        // "8 0z" -> "8 oz"
        cleaned = cleaned.replacing(/(\d\s?)0z\b/) { "\($0.1)oz" }
        // "l/2 cup" -> "1/2 cup", "I/4" -> "1/4"
        cleaned = cleaned.replacing(/\b[lI]\/(\d)/) { "1/\($0.1)" }
        // "l cup" / "I cup" at the start of a line -> "1 cup"
        cleaned = cleaned.replacing(
            /^[lI] (cups?|tsp|tbsp|teaspoons?|tablespoons?|lbs?|pounds?|oz|ounces?|cloves?|cans?)\b/.anchorsMatchLineEndings()
        ) { "1 \($0.1)" }
        return cleaned
    }
}
