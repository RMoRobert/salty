//
//  RecipeParser.swift
//  Salty
//
//  Created by Robert on 7/13/25.
//

import Foundation
import OSLog

struct RecipeParser {
    private let logger = Logger(subsystem: "Salty", category: "App")
    
    func parseRecipe(from text: String) -> Recipe {
        let lines = text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        
        var recipe = Recipe(
            id: UUID().uuidString,
            name: "",
            createdDate: Date(),
            lastModifiedDate: Date()
        )
        
        // Try to identify recipe name
        recipe.name = extractRecipeName(from: lines)
        
        // Try to identify ingredients
        recipe.ingredients = extractIngredients(from: lines)
        
        // Try to identify directions
        recipe.directions = extractDirections(from: lines)
        
        logger.info("Parsed recipe: '\(recipe.name)' with \(recipe.ingredients.count) ingredients and \(recipe.directions.count) directions")
        
        return recipe
    }
    
    private func extractRecipeName(from lines: [String]) -> String {
        // Look for common patterns in the first few lines
        for (index, line) in lines.prefix(5).enumerated() {
            let lowercased = line.lowercased()
            
            // Skip lines that are clearly not recipe names
            if lowercased.contains("ingredients") || 
               lowercased.contains("directions") ||
               lowercased.contains("instructions") ||
                lowercased.contains("prep time") ||
                lowercased.contains("preparation time") ||
               lowercased.contains("cook time") ||
               lowercased.contains("servings") ||
               lowercased.contains("yield") {
                continue
            }
            
            // Skip lines that look like ingredient measurements
            if isIngredientMeasurement(line) {
                continue
            }
            
            // Skip lines that are just numbers (step numbers)
            if line.matches(of: /^\d+\.?\s*$/).count > 0 {
                continue
            }
            
            // If we find a reasonable line, use it as the recipe name
            if line.count > 3 && line.count < 100 {
                return line
            }
        }
        
        return "New Recipe"
    }
    
    private func extractIngredients(from lines: [String]) -> [Ingredient] {
        var ingredients: [Ingredient] = []
        var inIngredientsSection = false
        var sectionStartIndex = -1
        
        // First pass: find the ingredients section
        for (index, line) in lines.enumerated() {
            let lowercased = line.lowercased()
            
            if lowercased.contains("ingredients") && !lowercased.contains("directions") {
                inIngredientsSection = true
                sectionStartIndex = index
                break
            }
        }
        
        // If no explicit ingredients section found, try to infer from patterns
        if !inIngredientsSection {
            return inferIngredientsFromPatterns(lines)
        }
        
        // Second pass: extract ingredients from the section
        for line in lines[(sectionStartIndex + 1)...] {
            let lowercased = line.lowercased()
            
            // Stop if we hit another major section
            if lowercased.contains("directions") || 
               lowercased.contains("instructions") ||
               lowercased.contains("method") ||
               lowercased.contains("steps") {
                break
            }
            
            // Skip empty lines and section headers
            if line.isEmpty || lowercased.contains("ingredients") {
                continue
            }
            
            // Add as ingredient (clean up bullet points and list delimiters)
            ingredients.append(Ingredient(
                id: UUID().uuidString,
                isHeading: false,
                isMain: false,
                text: cleanIngredientText(line)
            ))
        }
        
        return ingredients
    }
    
    private func inferIngredientsFromPatterns(_ lines: [String]) -> [Ingredient] {
        var ingredients: [Ingredient] = []
        
        for line in lines {
            // Look for common ingredient patterns
            if isIngredientMeasurement(line) || 
               line.contains("cup") ||
               line.contains("tablespoon") ||
               line.contains("teaspoon") ||
               line.contains("tbsp") ||
               line.contains("tsp") ||
               line.contains("ounce") ||
               line.contains("oz") ||
               line.contains("pound") ||
               line.contains("lb") ||
               line.contains("gram") ||
               line.contains("g") ||
               line.contains("ml") ||
               line.contains("clove") ||
               line.contains("pinch") ||
               line.contains("dash") {
                
                ingredients.append(Ingredient(
                    id: UUID().uuidString,
                    isHeading: false,
                    isMain: false,
                    text: cleanIngredientText(line)
                ))
            }
        }
        
        return ingredients
    }
    
    private func extractDirections(from lines: [String]) -> [Direction] {
        var directions: [Direction] = []
        var inDirectionsSection = false
        var sectionStartIndex = -1
        
        // First pass: find the directions section
        for (index, line) in lines.enumerated() {
            let lowercased = line.lowercased()
            
            if lowercased.contains("directions") || 
               lowercased.contains("instructions") ||
               lowercased.contains("method") ||
               lowercased.contains("steps") {
                inDirectionsSection = true
                sectionStartIndex = index
                break
            }
        }
        
        // If no explicit directions section found, try to infer from patterns
        if !inDirectionsSection {
            return inferDirectionsFromPatterns(lines)
        }
        
        // Second pass: extract directions from the section
        for line in lines[(sectionStartIndex + 1)...] {
            let lowercased = line.lowercased()
            
            // Stop if we hit another major section
            if lowercased.contains("ingredients") ||
               lowercased.contains("notes") ||
               lowercased.contains("tips") {
                break
            }
            
            // Skip empty lines and section headers
            if line.isEmpty || 
               lowercased.contains("directions") ||
               lowercased.contains("instructions") {
                continue
            }
            
            // Add as direction (clean up step numbers)
            directions.append(Direction(
                id: UUID().uuidString,
                isHeading: false,
                text: cleanDirectionText(line)
            ))
        }
        
        return directions
    }
    
    private func inferDirectionsFromPatterns(_ lines: [String]) -> [Direction] {
        var directions: [Direction] = []
        
        for line in lines {
            // Look for common direction patterns
            if line.matches(of: /^\d+\.?\s*/).count > 0 || // Numbered steps
               line.contains("heat") ||
               line.contains("add") ||
               line.contains("mix") ||
               line.contains("stir") ||
               line.contains("combine") ||
               line.contains("preheat") ||
               line.contains("bake") ||
               line.contains("cook") ||
               line.contains("simmer") ||
               line.contains("boil") ||
               line.contains("pour") ||
               line.contains("place") ||
               line.contains("remove") ||
               line.contains("let") ||
               line.contains("allow") ||
               line.contains("until") {
                
                directions.append(Direction(
                    id: UUID().uuidString,
                    isHeading: false,
                    text: cleanDirectionText(line)
                ))
            }
        }
        
        return directions
    }
    
    private func isIngredientMeasurement(_ line: String) -> Bool {
        let lowercased = line.lowercased()
        
        // Look for measurement patterns
        let measurementPatterns = [
            /^\d+\/\d+/, // Fractions like 1/2
            /^\d+\.\d+/, // Decimals like 1.5
            /^\d+\s+/,   // Numbers followed by space
        ]
        
        for pattern in measurementPatterns {
            if lowercased.matches(of: pattern).count > 0 {
                return true
            }
        }
        
        // Look for common measurement units
        let units = ["cup", "tablespoon", "teaspoon", "tbsp", "tsp", "ounce", "oz", "pound", "lb", "gram", "g", "ml", "clove", "pinch", "dash"]
        
        return units.contains { unit in
            lowercased.contains(unit)
        }
    }
    
    private func cleanIngredientText(_ text: String) -> String {
        var cleanedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Remove common bullet points and list delimiters
        let bulletPatterns = [
            /^•\s*/, // Bullet point
            /^-\s*/, // Dash
            /^\*\s*/, // Asterisk
            /^\+\s*/, // Plus sign
            /^>\s*/, // Greater than
            /^→\s*/, // Arrow
            /^▪\s*/, // Small bullet
            /^▫\s*/, // White bullet
            /^‣\s*/, // Triangular bullet
            /^⁃\s*/, // Hyphen bullet
            /^\d+\.\s*/, // Numbered list (1. 2. etc.)
            /^\d+\)\s*/, // Numbered list with parenthesis (1) 2) etc.)
            /^[a-zA-Z]\.\s*/, // Lettered list (a. b. etc.)
            /^[a-zA-Z]\)\s*/ // Lettered list with parenthesis (a) b) etc.)
        ]
        
        for pattern in bulletPatterns {
            cleanedText = cleanedText.replacing(pattern, with: "")
        }
        
        return cleanedText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func cleanDirectionText(_ text: String) -> String {
        var cleanedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Remove step numbers at the beginning
        let stepNumberPatterns = [
            /^\d+\.\s*/, // 1. 2. etc.
            /^\d+\)\s*/, // 1) 2) etc.
            /^[Ss]tep\s*\d+:?\s*/, // Step 1: Step 2 etc.
            /^\d+:\s*/, // 1: 2: etc.
            /^\d+\s+-\s*/, // 1 - 2 - etc.
            /^[a-zA-Z]\.\s*/, // a. b. etc.
            /^[a-zA-Z]\)\s*/ // a) b) etc.
        ]
        
        for pattern in stepNumberPatterns {
            cleanedText = cleanedText.replacing(pattern, with: "")
        }
        
        return cleanedText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
} 
