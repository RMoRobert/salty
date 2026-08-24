//
//  IngredientTextParser.swift
//  Salty
//
//  Created by Robert on 7/14/25
//

import Foundation
import UUIDV7

/// Utility class for parsing and formatting ingredient text from bulk text editor
public struct IngredientTextParser {
    
    /// Parses bulk text into Ingredient objects
    /// - Parameter text: Raw text input with ingredients
    /// - Returns: Array of Ingredient objects. Main ingredients are marked with [*] at the end of the line.
    public static func parseIngredients(from text: String) -> [Ingredient] {
        let lines = text.components(separatedBy: .newlines)
        var ingredients: [Ingredient] = []
        
        var i = 0
        while i < lines.count {
            var line = lines[i].trimmingCharacters(in: .whitespaces)
            
            if line.isEmpty {
                // Skip empty lines
                i += 1
                continue
            }
            
            // Check if this line is preceded by a blank line, making it a heading:
            let isHeadingByLine = i > 0 && lines[i - 1].trimmingCharacters(in: .whitespaces).isEmpty
            // Check if this line ends with a colon, making it a heading using the alternate format:
            let isHeadingByColon = line.hasSuffix(":")
            if isHeadingByColon {
                // strip colon for cleanliness
                line = String(line.dropLast())
            }
            let isHeading = isHeadingByLine || isHeadingByColon
            
            // Check for [*] marker at the end of the line to indicate main ingredient
            var isMain = false
            if !isHeading && line.hasSuffix("[*]") {
                isMain = true
                // Remove the [*] marker from the text
                line = String(line.dropLast(3)).trimmingCharacters(in: .whitespaces)
            }
            
            let ingredient = Ingredient(
                id: UUIDV7().uuidString,
                isHeading: isHeading,
                isMain: isMain,
                text: line
            )
            
            ingredients.append(ingredient)
            i += 1
        }
        
        return ingredients
    }
    
    /// Formats Ingredient objects into text for editing
    /// - Parameter ingredients: Array of Ingredient objects
    /// - Returns: Formatted text string. Main ingredients are marked with [*] at the end of the line.
    public static func formatIngredients(_ ingredients: [Ingredient]) -> String {
        var lines: [String] = []
        
        for ingredient in ingredients {
            if ingredient.isHeading {
                // Add blank line before heading
                lines.append("")
                lines.append(ingredient.text)
            } else {
                // Append [*] marker for main ingredients
                let text = ingredient.isMain ? "\(ingredient.text) [*]" : ingredient.text
                lines.append(text)
            }
        }
        
        return lines.joined(separator: "\n")
    }
    
    /// Cleans up text by removing list markers (more conservative than directions)
    /// - Parameter text: Raw text to clean
    /// - Returns: Cleaned text
    public static func cleanUpText(_ text: String) -> String {
        let lines = text.components(separatedBy: .newlines)
        let cleanedLines = lines.map { line in
            var cleanedLine = line.trimmingCharacters(in: .whitespaces)
            
            // Remove common list markers from the beginning
            let markers = ["*", "-", "•", "○", "▪", "▫", "‣", "⁃"]
            for marker in markers {
                if cleanedLine.hasPrefix(marker) {
                    cleanedLine = String(cleanedLine.dropFirst(marker.count))
                    break
                }
            }
            return cleanedLine.trimmingCharacters(in: .whitespaces)
        }
        return cleanedLines.joined(separator: "\n")
    }
    
    /// Simple parsing for basic use cases (like web extraction)
    /// - Parameter text: Raw text input
    /// - Returns: Array of Ingredient objects with no heading detection
    public static func parseIngredientsSimple(from text: String) -> [Ingredient] {
        let lines = text.components(separatedBy: .newlines)
        var ingredients: [Ingredient] = []
        
        for line in lines {
            let cleanLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleanLine.isEmpty {
                let ingredient = Ingredient(
                    id: UUIDV7().uuidString,
                    isHeading: false,
                    isMain: false,
                    text: cleanLine
                )
                ingredients.append(ingredient)
            }
        }
        
        return ingredients
    }
    
    /// Simple parsing with cleanup for web extraction
    /// - Parameter text: Raw text input
    /// - Returns: Array of Ingredient objects with no heading detection, cleaned up
    public static func parseIngredientsSimpleWithCleanup(from text: String) -> [Ingredient] {
        let cleanedText = cleanUpText(text)
        return parseIngredientsSimple(from: cleanedText)
    }
} 


/// Utility struct extension for parsing quantity out of ingredient string (used in UI)
extension Ingredient {
    /// Parses the ingredient text to identify the quantity portion (number + unit).
    /// Returns a tuple with the quantity string and the remainder of the text.
    public func parseQuantity() -> (quantity: String, remainder: String) {
        let trimmedText = text.trimmingCharacters(in: .whitespaces)
        
        let numberToken = #"\d+(?:\.\d+)?(?:\s+\d+/\d+)?(?:\s*/\s*\d+)?"#
        let rangePattern = #"^(\#(numberToken))\s*-\s*(\#(numberToken))"#
        
        var numberString: String
        var afterNumber: String
        
        if let rangeRegex = try? NSRegularExpression(pattern: rangePattern),
           let match = rangeRegex.firstMatch(in: trimmedText, range: NSRange(trimmedText.startIndex..., in: trimmedText)),
           match.numberOfRanges >= 3,
           let lowRange = Range(match.range(at: 1), in: trimmedText),
           let highRange = Range(match.range(at: 2), in: trimmedText) {
            numberString = "\(trimmedText[lowRange])-\(trimmedText[highRange])"
            afterNumber = String(trimmedText[highRange.upperBound...]).trimmingCharacters(in: .whitespaces)
        } else {
            // Check if text starts with a number (including fractions like 1/2, 1 1/2, decimals)
            let numberPattern = #"^(\#(numberToken))"#
            guard let numberRange = trimmedText.range(of: numberPattern, options: .regularExpression) else {
                return ("", trimmedText)
            }
            numberString = String(trimmedText[numberRange])
            afterNumber = String(trimmedText[numberRange.upperBound...]).trimmingCharacters(in: .whitespaces)
        }
        
        // If there's nothing after the number, return it as quantity
        guard !afterNumber.isEmpty else {
            return (numberString, "")
        }
        
        // Check for multi-word units first (e.g., "fl oz", "fluid ounce")
        let multiWordUnits: [String] = [
            "fl oz", "fl. oz.", "floz",
            "fluid ounce", "fluid ounces"
        ]
        
        let afterNumberLower = afterNumber.lowercased()
        for unit in multiWordUnits {
            let unitLower = unit.lowercased()
            if afterNumberLower.hasPrefix(unitLower) {
                // Find the actual unit string in the original text (preserving case)
                // We need to match character by character to handle case variations
                let unitLength = unit.count
                if afterNumber.count >= unitLength {
                    // Try to find the unit match preserving original case
                    let possibleUnit = String(afterNumber.prefix(unitLength))
                    if possibleUnit.lowercased() == unitLower {
                        let afterUnit = String(afterNumber.dropFirst(unitLength)).trimmingCharacters(in: .whitespaces)
                        let fullQuantity = "\(numberString) \(possibleUnit)"
                        return (fullQuantity, afterUnit)
                    }
                }
            }
        }
        
        // Extract the next word/token (may include periods, hyphens, etc.)
        let wordPattern = #"^([\w\.\-]+)"#
        guard let wordRange = afterNumber.range(of: wordPattern, options: .regularExpression) else {
            return (numberString, afterNumber)
        }
        
        let word = String(afterNumber[wordRange]).lowercased()
        let afterWord = String(afterNumber[wordRange.upperBound...]).trimmingCharacters(in: .whitespaces)
        
        // Check if the word is a unit of measurement
        let units: Set<String> = [
            "cup", "cups", "c", "c.",
            "tablespoon", "tablespoons", "tbl", "tbl.", "tbsp", "tbsp.", "tbs", "tbs.",
            "teaspoon", "teaspoons", "t", "t.", "tsp", "tsp.",
            "gram", "grams", "g", "g.",
            "kilogram", "kilograms", "kg", "kg.",
            "ounce", "ounces", "oz", "oz.",
            "pound", "pounds", "lb", "lb.", "lbs", "lbs.",
            "milliliter", "milliliters", "ml", "ml.",
            "liter", "liters", "l", "l.",
            "package", "packages", "pkg", "pkg.",
            "can", "cans",
            "bottle", "bottles",
            "piece", "pieces", "pc", "pc.",
            "dash", "dashes",
            "pinch", "pinches",
            "drop", "drops"
        ]
        
        // Check if word (with or without trailing period) matches a unit
        let wordWithoutPeriod = word.replacingOccurrences(of: ".", with: "")
        if units.contains(word) || units.contains(wordWithoutPeriod) {
            let fullQuantity = "\(numberString) \(String(afterNumber[wordRange]))"
            return (fullQuantity, afterWord)
        }
        
        // If not a unit, return just the number as quantity
        return (numberString, afterNumber)
    }
}
