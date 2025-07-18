//
//  IngredientTextParser.swift
//  Salty
//
//  Created by Robert on 7/14/25
//

import Foundation

/// Utility class for parsing and formatting ingredient text
struct IngredientTextParser {
    
    /// Parses bulk text into Ingredient objects
    /// - Parameters:
    ///   - text: Raw text input with ingredients
    ///   - existingIngredients: Existing ingredients to preserve isMain property
    /// - Returns: Array of Ingredient objects, including attempt to match isMain status from existing names
    static func parseIngredients(from text: String, preservingMainStatusFrom existingIngredients: [Ingredient] = []) -> [Ingredient] {
        let lines = text.components(separatedBy: .newlines)
        var ingredients: [Ingredient] = []
        
        // Create a mapping of existing ingredient text to isMain value for preservation
        var isMainPreservation: [String: Bool] = [:]
        for ingredient in existingIngredients {
            isMainPreservation[ingredient.text] = ingredient.isMain
        }
        
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
            
            let ingredient = Ingredient(
                id: UUID().uuidString,
                isHeading: isHeading,
                isMain: (isMainPreservation[line] ?? false) && !isHeading, // Preserve isMain if possible
                text: line
            )
            
            ingredients.append(ingredient)
            i += 1
        }
        
        return ingredients
    }
    
    /// Formats Ingredient objects into text for editing
    /// - Parameter ingredients: Array of Ingredient objects
    /// - Returns: Formatted text string
    static func formatIngredients(_ ingredients: [Ingredient]) -> String {
        var lines: [String] = []
        
        for ingredient in ingredients {
            if ingredient.isHeading {
                // Add blank line before heading
                lines.append("")
                lines.append(ingredient.text)
            } else {
                lines.append(ingredient.text)
            }
        }
        
        return lines.joined(separator: "\n")
    }
    
    /// Cleans up text by removing list markers (more conservative than directions)
    /// - Parameter text: Raw text to clean
    /// - Returns: Cleaned text
    static func cleanUpText(_ text: String) -> String {
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
    static func parseIngredientsSimple(from text: String) -> [Ingredient] {
        let lines = text.components(separatedBy: .newlines)
        var ingredients: [Ingredient] = []
        
        for line in lines {
            let cleanLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleanLine.isEmpty {
                let ingredient = Ingredient(
                    id: UUID().uuidString,
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
    static func parseIngredientsSimpleWithCleanup(from text: String) -> [Ingredient] {
        let cleanedText = cleanUpText(text)
        return parseIngredientsSimple(from: cleanedText)
    }
} 