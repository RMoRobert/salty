//
//  RecipeFromTextParser.swift
//  SaltyCore
//
//  Created by Robert on 7/13/25.
//
//  The rule-based reading of a recipe out of plain text (OCR, a pasted page): the fallback on every
//  device without Smart Parse, and the source of yield and servings even with it.
//
//  Vocabulary is matched as whole words. Substring matching once classed any line containing the
//  letter "g" (the gram unit) as an ingredient, so "Grandma's Lasagna" could never be a title and a
//  step mentioning ginger was swept into the ingredient list.
//

import Foundation
import UUIDV7

public struct RecipeFromTextParser {

    /// Stateless: the parser holds nothing, so this exists only to expose the (otherwise internal)
    /// synthesised init to callers outside SaltyCore.
    public init() {}

    private let logger = SaltyLogger(subsystem: "Salty", category: "App")

    // MARK: - Main parsing method

    public func parseRecipe(from text: String) -> Recipe {
        var lines = Self.lines(of: text)

        var recipe = Recipe(
            id: UUIDV7().uuidString,
            name: "",
            createdDate: Date(),
            lastModifiedDate: Date()
        )

        // Extract recipe name using improved logic
        recipe.name = extractRecipeName(from: lines)

        // The title line is not also an ingredient or a step, however many foods it names.
        if let titleIndex = lines.firstIndex(where: { cleanRecipeName($0) == recipe.name }) {
            lines.remove(at: titleIndex)
        }

        // Extract ingredients with better pattern recognition
        recipe.ingredients = extractIngredients(from: lines)

        // Extract directions with improved step detection
        recipe.directions = extractDirections(from: lines)

        // Extract additional metadata
        let metadata = extractMetadata(from: lines)
        recipe.yield = metadata.yield
        recipe.servings = metadata.servings
        recipe.introduction = metadata.introduction

        logger.info("Parsed recipe: '\(recipe.name)' with \(recipe.ingredients.count) ingredients and \(recipe.directions.count) directions")

        return recipe
    }

    // MARK: - Section scans

    /// Every line of `text` that is not a heading or a metadata line, as an ingredient each.
    ///
    /// For text scanned straight into the editor's ingredient list: the user has already said what the
    /// lines are, so nothing is judged by how it reads. Bullets and list numbers are stripped.
    public func parseIngredientLines(_ text: String) -> [Ingredient] {
        Self.lines(of: text).compactMap { line in
            guard !isSectionHeader(line), !isMetadataLine(line) else { return nil }
            let cleaned = cleanIngredientText(line)
            guard cleaned.count >= 2 else { return nil }
            return Ingredient(id: UUIDV7().uuidString, isHeading: false, isMain: false, text: cleaned)
        }
    }

    /// The steps in `text`, for text scanned straight into the editor's directions.
    ///
    /// A numbered line ("1.", "Step 2:", "3)") starts a step and unnumbered lines continue the one
    /// before, so a paragraph scanned as several lines comes back as one step. Headings and metadata
    /// lines are dropped, as are steps shorter than five characters, which are OCR noise.
    public func parseDirectionSteps(_ text: String) -> [Direction] {
        var directions: [Direction] = []
        var current = ""

        func finishStep() {
            let cleaned = cleanDirectionText(current)
            if cleaned.count >= 5 {
                directions.append(Direction(id: UUIDV7().uuidString, isHeading: false, text: cleaned))
            }
            current = ""
        }

        for line in Self.lines(of: text) where line.count >= 3 && !isSectionHeader(line) && !isMetadataLine(line) {
            if isDirectionStep(line) {
                if !current.isEmpty { finishStep() }
                current = line
            } else if current.isEmpty {
                current = line
            } else {
                current += " " + line
            }
        }
        if !current.isEmpty { finishStep() }
        return directions
    }

    /// The non-empty lines of `text`, trimmed.
    private static func lines(of text: String) -> [String] {
        text.components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
    }

    // MARK: - Recipe Name Extraction

    private func extractRecipeName(from lines: [String]) -> String {
        // Look for title-like patterns in the first few lines
        for line in lines.prefix(15) {
            let lowercased = line.lowercased()

            // The title comes before the recipe's sections: past the first Ingredients, Directions or
            // Notes heading every line belongs to a section, and "Salt and pepper to taste" is not a name.
            if isIngredientsSectionHeader(line) || isDirectionsSectionHeader(line) || isNotesSectionHeader(line) {
                break
            }

            // Skip lines that are clearly not recipe names
            if isSectionHeader(lowercased) ||
               isIngredientMeasurement(line) ||
               isDirectionStep(line) ||
               isMetadataLine(lowercased) {
                continue
            }

            let tokenCount = line.wordCount

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

    private static let titleFoodWords: Set<String> = [
        "recipe", "chicken", "beef", "pork", "fish", "salmon", "pasta", "soup", "salad", "cake", "bread",
        "cookie", "pie", "sauce", "dressing", "dip", "casserole", "stew", "curry", "stir", "fry", "grill",
        "bake", "roast", "steak", "burger", "pizza", "lasagna", "enchilada", "taco", "burrito", "sushi",
        "rice", "quinoa", "bean", "lentil", "tofu", "vegetable", "fruit", "berry", "apple", "banana",
        "orange", "lemon", "lime", "garlic", "onion", "tomato", "potato", "carrot", "broccoli", "spinach",
        "kale", "mushroom", "cheese", "milk", "cream", "butter", "oil", "vinegar", "herb", "spice", "salt",
        "pepper", "sugar", "flour", "egg", "meat", "seafood",
    ]

    private static let nonTitleStartWords: Set<String> = [
        "ingredients", "directions", "instructions", "method", "steps", "prep", "cook", "total",
        "servings", "yield", "preheat", "heat", "add", "mix", "combine", "stir", "pour", "place",
        "remove", "let", "allow", "until", "then", "next", "finally", "serve", "garnish", "enjoy",
    ]

    private func hasTitleCharacteristics(_ line: String, tokenCount: Int) -> Bool {
        // Title characteristics:
        // 1. Reasonable length (not too short, not too long)
        // 2. Contains food-related words
        // 3. Doesn't start with common non-title words
        // 4. May have capitalization patterns

        // Check if line starts with a non-title word ("Preheat the oven", "Serves 4")
        if let first = Self.words(in: line).first, Self.nonTitleStartWords.contains(first) {
            return false
        }

        // Check if line contains food-related words
        let hasFoodWords = Self.hasWholeWord(line, from: Self.titleFoodWords)

        // Check for reasonable capitalization (not all caps, not all lowercase)
        let hasMixedCase = line != line.uppercased() && line != line.lowercased()

        // Check for reasonable length
        let reasonableLength = line.count >= 5 && line.count <= 80

        return hasFoodWords || (hasMixedCase && reasonableLength)
    }

    // MARK: - Ingredients Extraction

    private func extractIngredients(from lines: [String]) -> [Ingredient] {
        var ingredients: [Ingredient] = []
        var inIngredientsSection = false
        var sectionStartIndex = -1

        // First pass: find the ingredients section
        for (index, line) in lines.enumerated() {
            if isIngredientsSectionHeader(line) {
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
            // Stop if we hit another major section
            if isDirectionsSectionHeader(line) || isNotesSectionHeader(line) {
                break
            }

            // Skip empty lines and section headers
            if line.isEmpty || isIngredientsSectionHeader(line) {
                continue
            }

            // Add as ingredient if it looks like an ingredient
            if isLikelyIngredient(line) {
                ingredients.append(Ingredient(
                    id: UUIDV7().uuidString,
                    isHeading: false,
                    isMain: false,
                    text: cleanIngredientText(line)
                ))
            }
        }

        return ingredients
    }

    private func inferIngredientsFromPatterns(_ lines: [String]) -> [Ingredient] {
        var ingredients: [Ingredient] = []

        for line in lines {
            if isLikelyIngredient(line) {
                ingredients.append(Ingredient(
                    id: UUIDV7().uuidString,
                    isHeading: false,
                    isMain: false,
                    text: cleanIngredientText(line)
                ))
            }
        }

        return ingredients
    }

    /// Units, in the forms a recipe writes them. Matched as whole words, so "g" is the gram in "250g"
    /// or "250 g" and nothing in "ginger" or "egg"; "c." keeps its period so a bare "c" is not a cup.
    private static let measurementUnits: Set<String> = [
        "cup", "cups", "c.", "tablespoon", "tablespoons", "tbl", "tbsp", "teaspoon", "teaspoons", "tsp",
        "ounce", "ounces", "oz", "pound", "pounds", "lb", "lbs", "gram", "grams", "g", "kg", "ml",
        "liter", "liters", "litre", "litres", "clove", "cloves", "pinch", "dash",
    ]

    private static let ingredientWords: Set<String> = measurementUnits.union([
        "can", "jar", "package", "bunch", "head", "stalk", "sprig", "whole", "half", "quarter", "third", "fourth",
    ])

    private static let foodItems: Set<String> = [
        "flour", "sugar", "salt", "pepper", "oil", "butter", "milk", "cream", "egg", "cheese", "meat",
        "chicken", "beef", "pork", "fish", "vegetable", "onion", "garlic", "tomato", "potato", "carrot",
        "broccoli", "spinach", "mushroom", "herb", "spice", "sauce", "vinegar", "lemon", "lime", "apple",
        "banana", "berry", "nut", "seed", "bean", "rice", "pasta", "bread", "cookie",
    ]

    private func isLikelyIngredient(_ line: String) -> Bool {
        // A quantity or a unit settles it.
        if isIngredientMeasurement(line) {
            return true
        }

        let words = Self.words(in: line)
        // A sentence that opens with a cooking verb is a step, however many foods it names.
        if let first = words.first, Self.isActionWord(first) {
            return false
        }
        // Check for reasonable ingredient length
        guard words.count <= 12, line.count >= 3, line.count <= 200 else { return false }

        // Check for common ingredient words and food items
        return Self.hasWholeWord(line, from: Self.ingredientWords) || Self.hasWholeWord(line, from: Self.foodItems)
    }

    // MARK: - Directions Extraction

    private func extractDirections(from lines: [String]) -> [Direction] {
        var directions: [Direction] = []
        var inDirectionsSection = false
        var sectionStartIndex = -1

        // First pass: find the directions section
        for (index, line) in lines.enumerated() {
            if isDirectionsSectionHeader(line) {
                inDirectionsSection = true
                sectionStartIndex = index
                logger.debug("Found directions section at line \(index): '\(line)'")
                break
            }
        }

        // If no explicit directions section found, try to infer from patterns
        if !inDirectionsSection {
            logger.debug("No explicit directions section found, using pattern inference")
            return inferDirectionsFromPatterns(lines)
        }

        // Second pass: extract directions from the section
        var currentDirection = ""

        for (index, line) in lines[(sectionStartIndex + 1)...].enumerated() {
            // Stop if we hit another major section
            if isIngredientsSectionHeader(line) || isNotesSectionHeader(line) {
                logger.debug("Stopping directions extraction at line \(sectionStartIndex + 1 + index): '\(line)'")
                break
            }

            // Skip empty lines, section headers, and metadata
            if line.isEmpty ||
               isDirectionsSectionHeader(line) ||
               isMetadataLine(line) {
                continue
            }

            // Check if this line starts a new step
            if isDirectionStep(line) {
                // Save the previous direction if we have one
                if !currentDirection.isEmpty {
                    directions.append(Direction(
                        id: UUIDV7().uuidString,
                        isHeading: false,
                        text: cleanDirectionText(currentDirection)
                    ))
                }

                // Start a new direction
                currentDirection = line
            } else {
                // Continue the current direction
                if !currentDirection.isEmpty {
                    currentDirection += " " + line
                } else if isLikelyDirection(line) {
                    // This might be a direction without a step number
                    currentDirection = line
                }
            }
        }

        // Add the last direction if we have one
        if !currentDirection.isEmpty {
            directions.append(Direction(
                id: UUIDV7().uuidString,
                isHeading: false,
                text: cleanDirectionText(currentDirection)
            ))
        }

        logger.debug("Extracted \(directions.count) directions")
        return directions
    }

    private func inferDirectionsFromPatterns(_ lines: [String]) -> [Direction] {
        var directions: [Direction] = []

        for line in lines {
            if isLikelyDirection(line) {
                directions.append(Direction(
                    id: UUIDV7().uuidString,
                    isHeading: false,
                    text: cleanDirectionText(line)
                ))
            }
        }

        return directions
    }

    /// Cooking verbs and the words that go with them, as stems: "stir" is also "stirring" and "stirred".
    private static let actionStems: Set<String> = [
        "heat", "add", "mix", "stir", "combine", "preheat", "bake", "cook", "simmer", "boil", "pour",
        "place", "remove", "let", "allow", "until", "then", "next", "finally", "serve", "garnish",
        "enjoy", "whisk", "beat", "fold", "knead", "roll", "cut", "chop", "dice", "mince", "slice",
        "grate", "peel", "wash", "drain", "rinse", "pat", "season", "sprinkle", "drizzle", "brush",
        "spray", "grease", "line", "cover", "uncover", "flip", "turn", "rotate", "shake", "toss",
        "sauté", "fry", "grill", "broil", "roast", "steam", "poach", "braise", "stew", "marinate",
        "rest", "cool", "chill", "freeze", "thaw", "defrost", "warm", "reheat", "process", "form",
        "press", "refrigerate", "bring", "reduce", "stand", "fluff", "meanwhile", "after", "degrees",
        "fahrenheit", "celsius",
    ]

    private func isLikelyDirection(_ line: String) -> Bool {
        // Skip metadata lines first
        if isMetadataLine(line) {
            return false
        }

        // Check for step numbers - if it's a step, it's definitely a direction
        if isDirectionStep(line) {
            return true
        }

        // Check for cooking action words
        let hasActionWords = Self.words(in: line).contains(where: Self.isActionWord)

        // Check for reasonable direction length (more lenient for complex recipes)
        let reasonableLength = line.count >= 8 && line.count <= 800

        // Additional check: make sure it's not just a time specification
        let isTimeSpec = line.lowercased().matches(of: /^\d+\s*(mins?|minutes?|hours?|hrs?)/).count > 0

        // Additional check: make sure it's not an ingredient
        let isIngredient = isLikelyIngredient(line)

        return hasActionWords && reasonableLength && !isTimeSpec && !isIngredient
    }

    // MARK: - Metadata Extraction

    private func extractMetadata(from lines: [String]) -> (yield: String, servings: Int?, introduction: String) {
        var yield = ""
        var servings: Int?
        var introduction = ""

        for line in lines {
            let lowercased = line.lowercased()

            // Yield and servings come from metadata lines only ("Makes 24 cookies", "Serves 4"), not
            // from a step that happens to say "until it makes a paste".
            if isMetadataLine(line) {
                if Self.hasWholeWord(line, from: ["yield", "yields", "makes"]) {
                    yield = extractYieldFromLine(line)
                }
                if Self.hasWholeWord(line, from: ["servings", "serves"]) {
                    servings = extractServingsFromLine(line)
                }
            }

            // Extract introduction (description before ingredients)
            if !isSectionHeader(lowercased) &&
               !isIngredientMeasurement(line) &&
               !isDirectionStep(line) &&
               !isMetadataLine(lowercased) &&
               !isLikelyIngredient(line) &&
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
            if let match = lowercased.matches(of: pattern).first,
               let number = Int(match.1) {
                return number
            }
        }

        return nil
    }

    // MARK: - Word matching

    /// The lowercase words of `line`, keeping a trailing period so "c." (cup) and "tbsp." survive.
    /// Digits and punctuation split words, so "250g" yields "g" and "INGREDIENTS:" yields "ingredients".
    private static func words(in line: String) -> [String] {
        line.lowercased().matches(of: /[a-zà-ÿ]+\.?/).map { String($0.output) }
    }

    /// `word` without a trailing period.
    private static func bare(_ word: String) -> String {
        word.hasSuffix(".") ? String(word.dropLast()) : word
    }

    /// Whether any word of `line` is in `vocabulary`, as a whole word; a trailing period and a plural
    /// "s" or "es" are tolerated ("tomatoes" matches "tomato", "tbsp." matches "tbsp").
    private static func hasWholeWord(_ line: String, from vocabulary: Set<String>) -> Bool {
        words(in: line).contains { token in
            let word = bare(token)
            if vocabulary.contains(token) || vocabulary.contains(word) { return true }
            if word.hasSuffix("es"), vocabulary.contains(String(word.dropLast(2))) { return true }
            if word.hasSuffix("s"), vocabulary.contains(String(word.dropLast())) { return true }
            return false
        }
    }

    /// Whether `word` is a cooking verb in any common form: "stir", "stirs", "stirred", "stirring".
    private static func isActionWord(_ word: String) -> Bool {
        let word = bare(word)
        if actionStems.contains(word) { return true }
        for suffix in ["ing", "ed", "es", "s", "d"] where word.hasSuffix(suffix) {
            let stem = String(word.dropLast(suffix.count))
            if actionStems.contains(stem) { return true }
            // The doubled consonant of "stirring" and "chopped".
            if stem.count >= 2, stem.last == stem.dropLast().last, actionStems.contains(String(stem.dropLast())) {
                return true
            }
        }
        return false
    }

    // MARK: - Helper Methods

    private static let sectionHeaderWords: Set<String> = [
        "ingredients", "ingredient", "directions", "instructions", "method", "steps", "preparation",
        "cooking", "notes", "tips", "variations", "nutrition", "servings", "yield",
    ]
    private static let sectionHeaderPhrases = ["prep time", "cook time", "total time"]

    /// Whether `line` is a section heading: a short line that opens with a heading word, like
    /// "Ingredients", "INGREDIENTS:", "Directions for the sauce" or "Prep time". Matching the word
    /// anywhere made "Mix the ingredients together" a heading (and the end of the steps) and
    /// "2 tbsp cooking oil" one too.
    private func isSectionHeader(_ line: String) -> Bool {
        Self.isHeading(line, startingWith: Self.sectionHeaderWords, orPhrases: Self.sectionHeaderPhrases)
    }

    private static func isHeading(_ line: String, startingWith headingWords: Set<String>, orPhrases phrases: [String] = []) -> Bool {
        let words = words(in: line).map(bare)
        guard let first = words.first, words.count <= 5 else { return false }
        if headingWords.contains(first) { return true }
        let joined = words.joined(separator: " ")
        return phrases.contains { joined.hasPrefix($0) }
    }

    private func isIngredientsSectionHeader(_ line: String) -> Bool {
        Self.isHeading(line, startingWith: ["ingredients", "ingredient"])
    }

    private func isDirectionsSectionHeader(_ line: String) -> Bool {
        Self.isHeading(line, startingWith: ["directions", "instructions", "method", "steps"])
    }

    private func isNotesSectionHeader(_ line: String) -> Bool {
        Self.isHeading(line, startingWith: ["notes", "tips", "variations"])
    }

    private static let metadataPhrases = ["prep time", "cook time", "total time", "additional time", "submitted by"]
    private static let metadataWords: Set<String> = ["servings", "yield", "yields", "makes", "serves"]

    /// Whether `line` carries recipe metadata: "Prep time: 10 min", "Serves 4", "Makes 24 cookies",
    /// "4 servings". A metadata word counts when it opens the line or the line is a few words long,
    /// so a step "until it makes a paste" is not one; "preserves" never was "serves".
    private func isMetadataLine(_ line: String) -> Bool {
        let words = Self.words(in: line).map(Self.bare)
        let joined = words.joined(separator: " ")
        if Self.metadataPhrases.contains(where: { joined.contains($0) }) { return true }
        if let first = words.first, Self.metadataWords.contains(first) { return true }
        return words.count <= 4 && words.contains { Self.metadataWords.contains($0) }
    }

    private func isIngredientMeasurement(_ line: String) -> Bool {
        let lowercased = line.lowercased()

        // Look for measurement patterns
        let measurementPatterns = [
            /^\d+\/\d+/, // Fractions like 1/2
            /^\d+\.\d+/, // Decimals like 1.5
            /^\d+\s+/,   // Numbers followed by space
            /^[½⅓⅔¼¾⅛⅜⅝⅞]/, // Vulgar fractions
        ]

        for pattern in measurementPatterns {
            if lowercased.matches(of: pattern).count > 0 {
                return true
            }
        }

        // Look for common measurement units, as whole words
        return Self.hasWholeWord(lowercased, from: Self.measurementUnits)
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

        return stepNumberPatterns.contains { line.matches(of: $0).count > 0 }
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
        cleanedText = cleanedText.replacing(/\s+/, with: " ")

        return cleanedText.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
