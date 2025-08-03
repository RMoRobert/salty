//
//  RecipeFromTextParser.swift
//  Salty
//
//  Created by Robert on 7/13/25.
//

import Foundation
import NaturalLanguage
import OSLog

struct RecipeFromTextParser {
    private let logger = Logger(subsystem: "Salty", category: "App")
    
    // MARK: - Main parsing method
    
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
        
        // Use NLTokenizer for better text analysis
        let tokenizer = NLTokenizer(unit: .sentence)
        tokenizer.string = text
        
        // Extract recipe name using improved logic
        recipe.name = extractRecipeName(from: lines, using: tokenizer)
        
        // Extract ingredients with better pattern recognition
        recipe.ingredients = extractIngredients(from: lines, using: tokenizer)
        
        // Extract directions with improved step detection
        recipe.directions = extractDirections(from: lines, using: tokenizer)
        
        // Extract additional metadata
        let metadata = extractMetadata(from: lines)
        recipe.yield = metadata.yield
        recipe.servings = metadata.servings
        recipe.introduction = metadata.introduction
        
        logger.info("Parsed recipe: '\(recipe.name)' with \(recipe.ingredients.count) ingredients and \(recipe.directions.count) directions")
        
        return recipe
    }
    
    // MARK: - Recipe Name Extraction
    
    private func extractRecipeName(from lines: [String], using tokenizer: NLTokenizer) -> String {
        // Look for title-like patterns in the first few lines
        for (index, line) in lines.prefix(15).enumerated() {
            let lowercased = line.lowercased()
            
            // Skip lines that are clearly not recipe names
            if isSectionHeader(lowercased) || 
               isIngredientMeasurement(line) ||
               isDirectionStep(line) ||
               isMetadataLine(lowercased) {
                continue
            }
            
            // Use NLTokenizer to analyze the line
            let lineTokenizer = NLTokenizer(unit: .word)
            lineTokenizer.string = line
            
            let tokenCount = lineTokenizer.tokens(for: line.startIndex..<line.endIndex).count
            
            // Skip very short or very long lines
            if tokenCount < 2 || tokenCount > 15 {
                continue
            }
            
            // Check for title-like characteristics
            if hasTitleCharacteristics(line, tokenCount: tokenCount) {
                return cleanRecipeName(line)
            }
        }
        
        return "New Recipe"
    }
    
    private func hasTitleCharacteristics(_ line: String, tokenCount: Int) -> Bool {
        // Title characteristics:
        // 1. Reasonable length (not too short, not too long)
        // 2. Contains food-related words
        // 3. Doesn't start with common non-title words
        // 4. May have capitalization patterns
        
        let foodWords = ["recipe", "chicken", "beef", "pork", "fish", "salmon", "pasta", "soup", "salad", "cake", "bread", "cookie", "pie", "sauce", "dressing", "dip", "casserole", "stew", "curry", "stir", "fry", "grill", "bake", "roast", "steak", "burger", "pizza", "lasagna", "enchilada", "taco", "burrito", "sushi", "rice", "quinoa", "bean", "lentil", "tofu", "vegetable", "fruit", "berry", "apple", "banana", "orange", "lemon", "lime", "garlic", "onion", "tomato", "potato", "carrot", "broccoli", "spinach", "kale", "mushroom", "cheese", "milk", "cream", "butter", "oil", "vinegar", "herb", "spice", "salt", "pepper", "sugar", "flour", "egg", "meat", "seafood"]
        
        let nonTitleStartWords = ["ingredients", "directions", "instructions", "method", "steps", "prep", "cook", "total", "servings", "yield", "preheat", "heat", "add", "mix", "combine", "stir", "pour", "place", "remove", "let", "allow", "until", "then", "next", "finally", "serve", "garnish", "enjoy"]
        
        let lowercased = line.lowercased()
        
        // Check if line starts with non-title words
        for word in nonTitleStartWords {
            if lowercased.hasPrefix(word) {
                return false
            }
        }
        
        // Check if line contains food-related words
        let hasFoodWords = foodWords.contains { foodWord in
            lowercased.contains(foodWord)
        }
        
        // Check for reasonable capitalization (not all caps, not all lowercase)
        let hasMixedCase = line != line.uppercased() && line != line.lowercased()
        
        // Check for reasonable length
        let reasonableLength = line.count >= 5 && line.count <= 80
        
        return hasFoodWords || (hasMixedCase && reasonableLength)
    }
    
    // MARK: - Ingredients Extraction
    
    private func extractIngredients(from lines: [String], using tokenizer: NLTokenizer) -> [Ingredient] {
        var ingredients: [Ingredient] = []
        var inIngredientsSection = false
        var sectionStartIndex = -1
        
        // First pass: find the ingredients section
        for (index, line) in lines.enumerated() {
            let lowercased = line.lowercased()
            
            if isIngredientsSectionHeader(lowercased) {
                inIngredientsSection = true
                sectionStartIndex = index
                break
            }
        }
        
        // If no explicit ingredients section found, try to infer from patterns
        if !inIngredientsSection {
            return inferIngredientsFromPatterns(lines, using: tokenizer)
        }
        
        // Second pass: extract ingredients from the section
        for line in lines[(sectionStartIndex + 1)...] {
            let lowercased = line.lowercased()
            
            // Stop if we hit another major section
            if isDirectionsSectionHeader(lowercased) || 
               isNotesSectionHeader(lowercased) {
                break
            }
            
            // Skip empty lines and section headers
            if line.isEmpty || isIngredientsSectionHeader(lowercased) {
                continue
            }
            
            // Add as ingredient if it looks like an ingredient
            if isLikelyIngredient(line, using: tokenizer) {
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
    
    private func inferIngredientsFromPatterns(_ lines: [String], using tokenizer: NLTokenizer) -> [Ingredient] {
        var ingredients: [Ingredient] = []
        
        for line in lines {
            if isLikelyIngredient(line, using: tokenizer) {
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
    
    private func isLikelyIngredient(_ line: String, using tokenizer: NLTokenizer) -> Bool {
        // Check for measurement patterns
        if isIngredientMeasurement(line) {
            return true
        }
        
        // Check for common ingredient words
        let ingredientWords = ["cup", "tablespoon", "teaspoon", "tbl", "tbsp", "tsp", "ounce", "oz", "pound", "lb", "gram", "g", "ml", "clove", "pinch", "dash", "can", "jar", "package", "bunch", "head", "stalk", "sprig", "slice", "chunk", "piece", "whole", "half", "quarter", "third", "fourth"]
        
        let hasIngredientWords = ingredientWords.contains { word in
            line.lowercased().contains(word)
        }
        
        // Check for food items
        let foodItems = ["flour", "sugar", "salt", "pepper", "oil", "butter", "milk", "cream", "egg", "cheese", "meat", "chicken", "beef", "pork", "fish", "vegetable", "onion", "garlic", "tomato", "potato", "carrot", "broccoli", "spinach", "mushroom", "herb", "spice", "sauce", "vinegar", "lemon", "lime", "apple", "banana", "berry", "nut", "seed", "bean", "rice", "pasta", "bread", "cookie", "oil"]
        
        let hasFoodItems = foodItems.contains { food in
            line.lowercased().contains(food)
        }
        
        // Check for reasonable ingredient length
        let reasonableLength = line.count >= 3 && line.count <= 200
        
        return hasIngredientWords || (hasFoodItems && reasonableLength)
    }
    
    // MARK: - Directions Extraction
    
    private func extractDirections(from lines: [String], using tokenizer: NLTokenizer) -> [Direction] {
        var directions: [Direction] = []
        var inDirectionsSection = false
        var sectionStartIndex = -1
        
        // First pass: find the directions section
        for (index, line) in lines.enumerated() {
            let lowercased = line.lowercased()
            
            if isDirectionsSectionHeader(lowercased) {
                inDirectionsSection = true
                sectionStartIndex = index
                logger.info("Found directions section at line \(index): '\(line)'")
                break
            }
        }
        
        // If no explicit directions section found, try to infer from patterns
        if !inDirectionsSection {
            logger.info("No explicit directions section found, using pattern inference")
            return inferDirectionsFromPatterns(lines, using: tokenizer)
        }
        
        // Second pass: extract directions from the section
        var currentDirection = ""
        var currentStepNumber = ""
        
        for (index, line) in lines[(sectionStartIndex + 1)...].enumerated() {
            let lowercased = line.lowercased()
            
            // Stop if we hit another major section
            if isIngredientsSectionHeader(lowercased) ||
               isNotesSectionHeader(lowercased) {
                logger.info("Stopping directions extraction at line \(sectionStartIndex + 1 + index): '\(line)'")
                break
            }
            
            // Skip empty lines, section headers, and metadata
            if line.isEmpty || 
               isDirectionsSectionHeader(lowercased) ||
               isMetadataLine(lowercased) {
                continue
            }
            
            // Check if this line starts a new step
            if isDirectionStep(line) {
                // Save the previous direction if we have one
                if !currentDirection.isEmpty {
                    directions.append(Direction(
                        id: UUID().uuidString,
                        isHeading: false,
                        text: cleanDirectionText(currentDirection)
                    ))
                    logger.info("Added direction: '\(currentDirection)'")
                }
                
                // Start a new direction
                currentStepNumber = line
                currentDirection = line
                logger.info("Started new step: '\(line)'")
            } else {
                // Continue the current direction
                if !currentDirection.isEmpty {
                    currentDirection += " " + line
                } else if isLikelyDirection(line, using: tokenizer) {
                    // This might be a direction without a step number
                    currentDirection = line
                }
            }
        }
        
        // Add the last direction if we have one
        if !currentDirection.isEmpty {
            directions.append(Direction(
                id: UUID().uuidString,
                isHeading: false,
                text: cleanDirectionText(currentDirection)
            ))
            logger.info("Added final direction: '\(currentDirection)'")
        }
        
        logger.info("Extracted \(directions.count) directions")
        return directions
    }
    
    private func inferDirectionsFromPatterns(_ lines: [String], using tokenizer: NLTokenizer) -> [Direction] {
        var directions: [Direction] = []
        
        for line in lines {
            if isLikelyDirection(line, using: tokenizer) {
                directions.append(Direction(
                    id: UUID().uuidString,
                    isHeading: false,
                    text: cleanDirectionText(line)
                ))
            }
        }
        
        return directions
    }
    
    private func isLikelyDirection(_ line: String, using tokenizer: NLTokenizer) -> Bool {
        // Skip metadata lines first
        if isMetadataLine(line) {
            return false
        }
        
        // Check for step numbers - if it's a step, it's definitely a direction
        if isDirectionStep(line) {
            logger.info("Line is a direction step: '\(line)'")
            return true
        }
        
        // Check for cooking action words (but exclude metadata-related words)
        let actionWords = ["heat", "add", "mix", "stir", "combine", "preheat", "bake", "cook", "simmer", "boil", "pour", "place", "remove", "let", "allow", "until", "then", "next", "finally", "serve", "garnish", "enjoy", "whisk", "beat", "fold", "knead", "roll", "cut", "chop", "dice", "mince", "slice", "grate", "peel", "wash", "drain", "rinse", "pat", "season", "sprinkle", "drizzle", "brush", "spray", "grease", "line", "cover", "uncover", "flip", "turn", "rotate", "shake", "toss", "sauté", "fry", "grill", "broil", "roast", "steam", "poach", "braise", "stew", "marinate", "rest", "cool", "chill", "freeze", "thaw", "defrost", "warm", "reheat", "drain", "rinse", "process", "form", "press", "refrigerate", "combine", "bring", "reduce", "cover", "simmer", "stand", "fluff", "add", "chill", "preheat", "grease", "meanwhile", "after", "degrees", "fahrenheit", "celsius"]
        
        let hasActionWords = actionWords.contains { action in
            line.lowercased().contains(action)
        }
        
        // Check for reasonable direction length (more lenient for complex recipes)
        let reasonableLength = line.count >= 8 && line.count <= 800
        
        // Additional check: make sure it's not just a time specification
        let isTimeSpec = line.lowercased().matches(of: /^\d+\s*(mins?|minutes?|hours?|hrs?)/).count > 0
        
        // Additional check: make sure it's not an ingredient
        let isIngredient = isLikelyIngredient(line, using: tokenizer)
        
        let result = hasActionWords && reasonableLength && !isTimeSpec && !isIngredient
        
        if result {
            logger.info("Line identified as direction: '\(line)'")
        }
        
        return result
    }
    
    // MARK: - Metadata Extraction
    
    private func extractMetadata(from lines: [String]) -> (yield: String, servings: Int?, introduction: String) {
        var yield = ""
        var servings: Int?
        var introduction = ""
        
        for line in lines {
            let lowercased = line.lowercased()
            
            // Extract yield information
            if lowercased.contains("yield") || lowercased.contains("makes") {
                yield = extractYieldFromLine(line)
            }
            
            // Extract servings information
            if lowercased.contains("servings") || lowercased.contains("serves") {
                servings = extractServingsFromLine(line)
            }
            
            // Extract introduction (description before ingredients)
            if !isSectionHeader(lowercased) && 
               !isIngredientMeasurement(line) &&
               !isDirectionStep(line) &&
               !isMetadataLine(lowercased) &&
               !isLikelyIngredient(line, using: NLTokenizer(unit: .word)) &&
               introduction.isEmpty &&
               line.count > 20 && line.count < 200 {
                introduction = line
            }
        }
        
        return (yield, servings, introduction)
    }
    
    private func extractYieldFromLine(_ line: String) -> String {
        // Extract yield information like "serves 4" or "yield: 6 servings"
        let lowercased = line.lowercased()
        let patterns = [
            /yield:?\s*([^,\.]+)/,
            /makes:?\s*([^,\.]+)/,
            /serves:?\s*([^,\.]+)/
        ]
        
        for pattern in patterns {
            if let match = lowercased.matches(of: pattern).first {
                return String(match.1).trimmingCharacters(in: .whitespacesAndNewlines)
            }
        }
        
        return ""
    }
    
    private func extractServingsFromLine(_ line: String) -> Int? {
        // Extract numeric servings information
        let lowercased = line.lowercased()
        let patterns = [
            /(\d+)\s*servings/,
            /serves\s*(\d+)/,
            /yield:?\s*(\d+)/,
            /makes\s*(\d+)/
        ]
        
        for pattern in patterns {
            if let match = line.matches(of: pattern).first,
               let number = Int(match.1) {
                return number
            }
        }
        
        return nil
    }
    
    // MARK: - Helper Methods
    
    private func isSectionHeader(_ line: String) -> Bool {
        let sectionHeaders = ["ingredients", "directions", "instructions", "method", "steps", "preparation", "cooking", "notes", "tips", "variations", "nutrition", "prep time", "cook time", "total time", "servings", "yield"]
        
        return sectionHeaders.contains { header in
            line.contains(header)
        }
    }
    
    private func isIngredientsSectionHeader(_ line: String) -> Bool {
        return line.contains("ingredients") && !line.contains("directions")
    }
    
    private func isDirectionsSectionHeader(_ line: String) -> Bool {
        let directionHeaders = ["directions", "instructions", "method", "steps"]
        return directionHeaders.contains { header in
            line.lowercased().contains(header)
        }
    }
    
    private func isNotesSectionHeader(_ line: String) -> Bool {
        let notesHeaders = ["notes", "tips", "variations"]
        return notesHeaders.contains { header in
            line.contains(header)
        }
    }
    
    private func isMetadataLine(_ line: String) -> Bool {
        let metadataPatterns = ["prep time", "cook time", "total time", "additional time", "servings", "yield", "makes", "serves", "submitted by", "prep time:", "cook time:", "total time:", "additional time:", "servings:", "yield:", "makes:", "serves:"]
        return metadataPatterns.contains { pattern in
            line.lowercased().contains(pattern)
        }
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
        let units = ["cup", "c.", "tablespoon", "Tbl", "tbsp", "teaspoon", "tsp", "ounce", "oz", "pound", "lb", "gram", "g", "ml", "clove", "pinch", "dash"]
        
        return units.contains { unit in
            lowercased.contains(unit)
        }
    }
    
    private func isDirectionStep(_ line: String) -> Bool {
        // Check for step numbers at the beginning
        let stepNumberPatterns = [
            /^\d+\.\s*/, // 1. 2. etc.
            /^\d+\)\s*/, // 1) 2) etc.
            /^[Ss]tep\s*\d+:?\s*/, // Step 1: Step 2 etc.
            /^\d+:\s*/, // 1: 2: etc.
            /^\d+\s+-\s*/, // 1 - 2 - etc.
            /^\s*\d+\.\s*/, // Indented numbered steps like "    1. "
            /^\s*[Ss]tep\s*\d+:?\s*/, // Indented Step 1: Step 2 etc.
        ]
        
        for (index, pattern) in stepNumberPatterns.enumerated() {
            if line.matches(of: pattern).count > 0 {
                logger.info("Line matches step pattern \(index): '\(line)'")
                return true
            }
        }
        
        return false
    }
    
    private func cleanRecipeName(_ text: String) -> String {
        var cleanedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Remove common prefixes/suffixes that might be in recipe names
        let lowercased = cleanedText.lowercased()
        let unwantedPrefixes = [
            "recipe:",
            "recipe ",
            "how to make ",
            "homemade ",
            "traditional "
        ]
        
        for prefix in unwantedPrefixes {
            if lowercased.hasPrefix(prefix) {
                let prefixLength = prefix.count
                cleanedText = String(cleanedText.dropFirst(prefixLength))
                break // Only remove the first matching prefix
            }
        }
        
        return cleanedText.trimmingCharacters(in: .whitespacesAndNewlines)
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
            /^\d+\.\s*/, // Numbered list with period: 1., 2., etc.
            /^\d+\)\s*/, // Numbered list with parenthesis: 1), 2), etc.
        ]
        
        for pattern in bulletPatterns {
            cleanedText = cleanedText.replacing(pattern, with: "")
        }
        
        return cleanedText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func cleanDirectionText(_ text: String) -> String {
        var cleanedText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Remove step numbers at the beginning (including indented ones)
        let stepNumberPatterns = [
            /^\d+\.\s*/, // 1. 2. etc.
            /^\d+\)\s*/, // 1) 2) etc.
            /^[Ss]tep\s*\d+:?\s*/, // Step 1: Step 2 etc.
            /^\d+:\s*/, // 1: 2: etc.
            /^\d+\s+-\s*/, // 1 - 2 - etc.
            /^\s*\d+\.\s*/, // Indented numbered steps like "    1. "
            /^\s*[Ss]tep\s*\d+:?\s*/, // Indented Step 1: Step 2 etc.
        ]
        
        for pattern in stepNumberPatterns {
            cleanedText = cleanedText.replacing(pattern, with: "")
        }
        
        // Clean up any extra whitespace that might be left
        cleanedText = cleanedText.replacingOccurrences(of: "\\s+", with: " ", options: .regularExpression)
        
        return cleanedText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
} 
