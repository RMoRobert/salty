//
//  SchemaOrgRecipeJSONLDImporter.swift
//  Salty
//
//  Created by Robert on 7/14/25.
//
// Purpose: Parse and import https://schema.org/Recipe data from JSON-LD, aiming for AllRecipes compatibility, though
// should be easily extendible to any site or data supporting this standard
//
// Usage Example:
// let importer = SchemaOrgRecipeJSONLDImporter()
// let recipes = importer.parseRecipes(from: htmlString)
// // or
// let recipes = await importer.parseRecipes(from: URL(string: "https://example.com/recipe")!)
//

import Foundation
import SwiftSoup
import OSLog

class SchemaOrgRecipeJSONLDImporter {
    private let logger = Logger(subsystem: "Salty", category: "App")
    
    // MARK: - Main parsing method
    
    /// Parses schema.org Recipe data from HTML containing JSON-LD
    /// - Parameter html: HTML content containing JSON-LD script tags
    /// - Returns: Array of Recipe objects found in the HTML
    func parseRecipes(from html: String) -> [Recipe] {
        var recipes: [Recipe] = []
        
        do {
            let doc = try SwiftSoup.parse(html)
            let scriptTags = try doc.select("script[type=application/ld+json]")
            
            logger.info("Found \(scriptTags.count) JSON-LD script tags")
            
            for scriptTag in scriptTags {
                let jsonContent = try scriptTag.html()
                
                if let jsonData = jsonContent.data(using: .utf8) {
                    let parsedRecipes = parseJSONLD(jsonData)
                    recipes.append(contentsOf: parsedRecipes)
                }
            }
            
        } catch {
            logger.error("Error parsing HTML: \(error)")
        }
        
        logger.info("Successfully parsed \(recipes.count) recipes from HTML")
        return recipes
    }
    
    // MARK: - JSON-LD parsing
    
    private func parseJSONLD(_ jsonData: Data) -> [Recipe] {
        var recipes: [Recipe] = []
        
        do {
            let json = try JSONSerialization.jsonObject(with: jsonData, options: [])
            
            if let jsonDict = json as? [String: Any] {
                // Handle single JSON-LD object
                if let recipe = parseRecipeFromJSONDict(jsonDict) {
                    recipes.append(recipe)
                }
                
                // Handle if nested in @graph array (Cookie and Kate, etc.)
                if let graph = jsonDict["@graph"] as? [[String: Any]] {
                    for item in graph {
                        if let recipe = parseRecipeFromJSONDict(item) {
                            recipes.append(recipe)
                        }
                    }
                }
                // Handle if at top level (AllRecipes, etc.):
            } else if let jsonArray = json as? [[String: Any]] {
                // Handle array of JSON-LD objects
                for item in jsonArray {
                    if let recipe = parseRecipeFromJSONDict(item) {
                        recipes.append(recipe)
                    }
                }
            }
            
        } catch {
            logger.error("Error parsing JSON-LD: \(error)")
        }
        
        return recipes
    }
    
    private func parseRecipeFromJSONDict(_ dict: [String: Any]) -> Recipe? {
        // Check if this is a Recipe type
        guard isRecipeType(dict) else {
            return nil
        }
        
        logger.info("Parsing Recipe from JSON-LD")
        
        let recipe = Recipe(
            id: UUID().uuidString,
            name: extractString(from: dict, key: "name") ?? "",
            createdDate: Date(),
            lastModifiedDate: Date(),
            lastPrepared: nil,
            source: extractAuthor(from: dict),
            sourceDetails: extractString(from: dict, key: "url") ?? "",
            introduction: extractString(from: dict, key: "description") ?? "",
            difficulty: .notSet, // haven't found in format, but is possible?
            //rating: extractRating(from: dict), // probably doesn't make sense; want user-supplied rating, if any
            rating: .notSet,
            imageFilename: nil,
            imageThumbnailData: nil,  // some sites do appear to ahve this data, so maybe something to look at in future
            isFavorite: false,
            wantToMake: false,
            yield: extractString(from: dict, key: "recipeYield") ?? "",
            servings: extractServings(from: dict),
            directions: extractDirections(from: dict),
            ingredients: extractIngredients(from: dict),
            notes: extractNotes(from: dict),
            preparationTimes: extractPreparationTimes(from: dict),
            nutrition: extractNutritionInformation(from: dict)
        )
        
        return recipe
    }
    
    // MARK: - Type checking
    
    private func isRecipeType(_ dict: [String: Any]) -> Bool {
        guard let type = dict["@type"] else {
            return false
        }
        
        // Handle string type
        if let typeString = type as? String {
            return typeString == "Recipe"
        }
        
        // Handle array of types
        if let typeArray = type as? [String] {
            return typeArray.contains("Recipe")
        }
        
        return false
    }
    
    // MARK: - Data extraction methods
    
    private func extractString(from dict: [String: Any], key: String) -> String? {
        if let value = dict[key] as? String {
            return value.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return nil
    }
    
    private func extractAuthor(from dict: [String: Any]) -> String {
        if let author = dict["author"] {
            // Handle string author
            if let authorString = author as? String {
                return authorString
            }
            
            // Handle object author
            if let authorDict = author as? [String: Any] {
                if let name = authorDict["name"] as? String {
                    return name
                }
            }
            
            // Handle array of authors
            if let authorArray = author as? [[String: Any]] {
                let names = authorArray.compactMap { $0["name"] as? String }
                return names.joined(separator: ", ")
            }
        }
        
        return ""
    }

// Probably doesn't make sense -- rating in app is user rating, not rating from site?
//    private func extractRating(from dict: [String: Any]) -> Rating {
//        if let aggregateRating = dict["aggregateRating"] as? [String: Any] {
//            if let ratingValue = aggregateRating["ratingValue"] as? Double {
//                // Convert to 1-5 scale
//                let roundedRating = Int(round(ratingValue))
//                return Rating(rawValue: min(max(roundedRating, 0), 5)) ?? .notSet
//            }
//            if let ratingValue = aggregateRating["ratingValue"] as? String,
//               let doubleValue = Double(ratingValue) {
//                let roundedRating = Int(round(doubleValue))
//                return Rating(rawValue: min(max(roundedRating, 0), 5)) ?? .notSet
//            }
//        }
//        return .notSet
//    }
    
    private func extractServings(from dict: [String: Any]) -> Int? {
        // Try recipeYield first
        if let yield = dict["recipeYield"] {
            if let yieldInt = yield as? Int {
                return yieldInt
            }
            if let yieldString = yield as? String {
                // Extract number from string like "4 servings" or "Serves 6"
                let numbers = yieldString.components(separatedBy: CharacterSet.decimalDigits.inverted).compactMap { Int($0) }
                return numbers.first
            }
        }
        
        // Try nutrition servingSize
        if let nutrition = dict["nutrition"] as? [String: Any],
           let servingSize = nutrition["servingSize"] as? String {
            let numbers = servingSize.components(separatedBy: CharacterSet.decimalDigits.inverted).compactMap { Int($0) }
            return numbers.first
        }
        
        return nil
    }
    
    private func extractDirections(from dict: [String: Any]) -> [Direction] {
        var directions: [Direction] = []
        
        if let recipeInstructions = dict["recipeInstructions"] {
            if let instructionsArray = recipeInstructions as? [[String: Any]] {
                for (index, instruction) in instructionsArray.enumerated() {
                    if let text = instruction["text"] as? String {
                        directions.append(Direction(
                            id: UUID().uuidString,
                            isHeading: false,
                            text: text.trimmingCharacters(in: .whitespacesAndNewlines)
                        ))
                    }
                }
            } else if let instructionsArray = recipeInstructions as? [String] {
                for instruction in instructionsArray {
                    directions.append(Direction(
                        id: UUID().uuidString,
                        isHeading: false,
                        text: instruction.trimmingCharacters(in: .whitespacesAndNewlines)
                    ))
                }
            } else if let instructionString = recipeInstructions as? String {
                // Handle single instruction string
                directions.append(Direction(
                    id: UUID().uuidString,
                    isHeading: false,
                    text: instructionString.trimmingCharacters(in: .whitespacesAndNewlines)
                ))
            }
        }
        
        return directions
    }
    
    private func extractIngredients(from dict: [String: Any]) -> [Ingredient] {
        var ingredients: [Ingredient] = []
        
        if let recipeIngredients = dict["recipeIngredient"] as? [String] {
            for ingredient in recipeIngredients {
                ingredients.append(Ingredient(
                    id: UUID().uuidString,
                    isHeading: false,
                    isMain: false,
                    text: ingredient.trimmingCharacters(in: .whitespacesAndNewlines)
                ))
            }
        }
        
        return ingredients
    }
    
    private func extractPreparationTimes(from dict: [String: Any]) -> [PreparationTime] {
        var preparationTimes: [PreparationTime] = []
        
        // Extract prep time
        if let prepTime = dict["prepTime"] as? String {
            let timeString = formatDuration(prepTime)
            preparationTimes.append(PreparationTime(
                id: UUID().uuidString,
                type: "Prep",
                timeString: timeString
            ))
        }
        
        // Extract cook time
        if let cookTime = dict["cookTime"] as? String {
            let timeString = formatDuration(cookTime)
            preparationTimes.append(PreparationTime(
                id: UUID().uuidString,
                type: "Cook",
                timeString: timeString
            ))
        }
        
        // Extract total time
        if let totalTime = dict["totalTime"] as? String {
            let timeString = formatDuration(totalTime)
            preparationTimes.append(PreparationTime(
                id: UUID().uuidString,
                type: "Total",
                timeString: timeString
            ))
        }
        
        return preparationTimes
    }
    
    private func extractImageURL(from dict: [String: Any]) -> String? {
        // Handle image field
        if let image = dict["image"] {
            // Handle string URL
            if let imageString = image as? String {
                return imageString
            }
            
            // Handle object with URL property
            if let imageDict = image as? [String: Any] {
                if let url = imageDict["url"] as? String {
                    return url
                }
            }
            
            // Handle array of images (take first one)
            if let imageArray = image as? [Any] {
                if let firstImage = imageArray.first {
                    if let imageString = firstImage as? String {
                        return imageString
                    }
                    if let imageDict = firstImage as? [String: Any],
                       let url = imageDict["url"] as? String {
                        return url
                    }
                }
            }
        }
        
        return nil
    }
    
    private func extractNotes(from dict: [String: Any]) -> [Note] {
        var notes: [Note] = []
        
        // Extract keywords as a note
        if let keywords = dict["keywords"] as? String, !keywords.isEmpty {
            notes.append(Note(
                id: UUID().uuidString,
                title: "Keywords",
                content: keywords
            ))
        }
        
        // Extract recipe category as a note
        if let category = dict["recipeCategory"] as? String, !category.isEmpty {
            notes.append(Note(
                id: UUID().uuidString,
                title: "Category",
                content: category
            ))
        }
        
        // Extract cuisine as a note
        if let cuisine = dict["recipeCuisine"] as? String, !cuisine.isEmpty {
            notes.append(Note(
                id: UUID().uuidString,
                title: "Cuisine",
                content: cuisine
            ))
        }
        
        // Note: Nutrition information is now extracted separately as structured data
        
        return notes
    }
    
    private func extractNutritionInformation(from dict: [String: Any]) -> NutritionInformation? {
        guard let nutrition = dict["nutrition"] as? [String: Any] else {
            return nil
        }
        
        var nutritionInfo = NutritionInformation()
        
        // Extract serving size
        if let servingSize = nutrition["servingSize"] as? String {
            nutritionInfo.servingSize = servingSize
        }
        
        // Extract calories
        if let calories = nutrition["calories"] as? String {
            nutritionInfo.calories = parseNutritionValue(calories)
        }
        
        // Extract macronutrients
        if let protein = nutrition["proteinContent"] as? String {
            nutritionInfo.protein = parseNutritionValue(protein)
        }
        
        if let carbs = nutrition["carbohydrateContent"] as? String {
            nutritionInfo.carbohydrates = parseNutritionValue(carbs)
        }
        
        if let fat = nutrition["fatContent"] as? String {
            nutritionInfo.fat = parseNutritionValue(fat)
        }
        
        if let saturatedFat = nutrition["saturatedFatContent"] as? String {
            nutritionInfo.saturatedFat = parseNutritionValue(saturatedFat)
        }
        
        if let transFat = nutrition["transFatContent"] as? String {
            nutritionInfo.transFat = parseNutritionValue(transFat)
        }
        
        if let fiber = nutrition["fiberContent"] as? String {
            nutritionInfo.fiber = parseNutritionValue(fiber)
        }
        
        if let sugar = nutrition["sugarContent"] as? String {
            nutritionInfo.sugar = parseNutritionValue(sugar)
        }
        
        if let sodium = nutrition["sodiumContent"] as? String {
            nutritionInfo.sodium = parseNutritionValue(sodium)
        }
        
        if let cholesterol = nutrition["cholesterolContent"] as? String {
            nutritionInfo.cholesterol = parseNutritionValue(cholesterol)
        }
        
        // Extract vitamins and minerals
        if let vitaminD = nutrition["vitaminDContent"] as? String {
            nutritionInfo.vitaminD = parseNutritionValue(vitaminD)
        }
        
        if let calcium = nutrition["calciumContent"] as? String {
            nutritionInfo.calcium = parseNutritionValue(calcium)
        }
        
        if let iron = nutrition["ironContent"] as? String {
            nutritionInfo.iron = parseNutritionValue(iron)
        }
        
        if let potassium = nutrition["potassiumContent"] as? String {
            nutritionInfo.potassium = parseNutritionValue(potassium)
        }
        
        if let vitaminA = nutrition["vitaminAContent"] as? String {
            nutritionInfo.vitaminA = parseNutritionValue(vitaminA)
        }
        
        if let vitaminC = nutrition["vitaminCContent"] as? String {
            nutritionInfo.vitaminC = parseNutritionValue(vitaminC)
        }
        
        // Check if we have any nutrition data
        let hasNutritionData = nutritionInfo.calories != nil ||
                              nutritionInfo.protein != nil ||
                              nutritionInfo.carbohydrates != nil ||
                              nutritionInfo.fat != nil ||
                              nutritionInfo.fiber != nil ||
                              nutritionInfo.sugar != nil ||
                              nutritionInfo.sodium != nil ||
                              nutritionInfo.cholesterol != nil ||
                              nutritionInfo.servingSize != nil
        
        return hasNutritionData ? nutritionInfo : nil
    }
    
    private func parseNutritionValue(_ value: String) -> Double? {
        // Extract numeric value from strings like "240 calories", "9g", "300mg"
        let cleanValue = value.replacingOccurrences(of: " calories", with: "")
                             .replacingOccurrences(of: "g", with: "")
                             .replacingOccurrences(of: "mg", with: "")
                             .replacingOccurrences(of: "mcg", with: "")
                             .replacingOccurrences(of: "µg", with: "")
                             .trimmingCharacters(in: .whitespacesAndNewlines)
        
        return Double(cleanValue)
    }
    
    // MARK: - Utility methods
    
    /// Converts ISO 8601 duration (PT15M) to human-readable format
    private func formatDuration(_ duration: String) -> String {
        // Handle ISO 8601 duration format (PT15M, PT1H30M, etc.)
        let cleanDuration = duration.uppercased()
        
        if cleanDuration.hasPrefix("PT") {
            let timeString = String(cleanDuration.dropFirst(2))
            var result: [String] = []
            
            // Extract hours
            if let hourRange = timeString.range(of: "H") {
                let hoursPart = String(timeString[..<hourRange.lowerBound])
                if let hours = Int(hoursPart) {
                    result.append("\(hours) hr")
                }
            }
            
            // Extract minutes
            if let minuteRange = timeString.range(of: "M") {
                let minutesPart = String(timeString[..<minuteRange.lowerBound])
                // Remove hours part if present
                let cleanMinutesPart = minutesPart.components(separatedBy: "H").last ?? minutesPart
                if let minutes = Int(cleanMinutesPart) {
                    result.append("\(minutes) min")
                }
            }
            
            return result.joined(separator: " ")
        }
        
        // Return as-is if not ISO 8601 format
        return duration
    }
}

// MARK: - Convenience extension for URL parsing

extension SchemaOrgRecipeJSONLDImporter {
    /// Convenience method to parse recipes from a URL
    /// - Parameter url: URL to fetch and parse
    /// - Returns: Array of Recipe objects found at the URL
    func parseRecipes(from url: URL) async -> [Recipe] {
        do {
            let (data, _) = try await URLSession.shared.data(from: url)
            if let html = String(data: data, encoding: .utf8) {
                return parseRecipes(from: html)
            }
        } catch {
            logger.error("Error fetching URL \(url): \(error)")
        }
        
        return []
    }
}
