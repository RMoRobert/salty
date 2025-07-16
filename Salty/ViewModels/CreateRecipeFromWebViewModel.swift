//
//  CreateRecipeFromWebViewModel.swift
//  Salty
//
//  Created by Assistant on 1/27/25.
//

import Foundation
import OSLog
import SharingGRDB

@Observable
@MainActor
class CreateRecipeFromWebViewModel {
    // MARK: - Constants
    private let logger = Logger(subsystem: "Salty", category: "CreateRecipeFromWeb")
    
    // MARK: - Dependencies
    @ObservationIgnored
    @Dependency(\.defaultDatabase) private var database
    
    // MARK: - Recipe State
    var recipe: Recipe
    
    // MARK: - Plain Text State for Import
    var ingredientsText: String = ""
    var directionsText: String = ""
    
    // MARK: - Web Browser State
    var currentURL: String = ""
    var canGoBack = false
    var canGoForward = false
    var isLoading = false
    
    // MARK: - UI State
    var showingCategoriesSheet = false
    var showingPreparationTimesSheet = false
    var showingImageEditSheet = false
    var showingNotesSheet = false
    var showingNutritionEditSheet = false
    var showingSaveAlert = false
    var showingCancelAlert = false
    
    // MARK: - Computed Properties
    var hasRecipeData: Bool {
        let hasBasicInfo = !recipe.name.isEmpty || 
                          !recipe.source.isEmpty || 
                          !recipe.sourceDetails.isEmpty || 
                          !recipe.introduction.isEmpty
        
        let hasStructuredContent = !recipe.ingredients.isEmpty ||
                                  !recipe.directions.isEmpty ||
                                  !recipe.notes.isEmpty
        
        let hasTextContent = !ingredientsText.isEmpty ||
                            !directionsText.isEmpty
        
        return hasBasicInfo || hasStructuredContent || hasTextContent
    }
    
    // MARK: - Initialization
    init() {
        self.recipe = Recipe(
            id: UUID().uuidString,
            name: "",
            createdDate: Date(),
            lastModifiedDate: Date()
        )
    }
    
    // MARK: - Recipe Management
    func saveRecipe() {
        // Convert text to structured data before saving
        convertTextToStructuredData()
        
        recipe.lastModifiedDate = Date()
        
        do {
            try database.write { db in
                try recipe.insert(db)
            }
            logger.info("Recipe saved successfully: \(self.recipe.id)")
        } catch {
            logger.error("Error saving recipe: \(error)")
        }
    }
    
    private func convertTextToStructuredData() {
        // Convert ingredients text to structured ingredients
        if !ingredientsText.isEmpty {
            recipe.ingredients = IngredientTextParser.parseIngredients(from: ingredientsText, preservingMainStatusFrom: recipe.ingredients)
        }
        
        // Convert directions text to structured directions
        if !directionsText.isEmpty {
            recipe.directions = DirectionTextParser.parseDirections(from: directionsText)
        }
    }

    
    func resetRecipe() {
        recipe = Recipe(
            id: UUID().uuidString,
            name: "",
            createdDate: Date(),
            lastModifiedDate: Date()
        )
        ingredientsText = ""
        directionsText = ""
    }
    
    func populateFromScannedRecipe(_ scannedRecipe: Recipe) {
        logger.info("Populating recipe from scanned data: \(scannedRecipe.name)")
        
        // Update basic recipe fields
        recipe.name = scannedRecipe.name
        recipe.source = scannedRecipe.source
        recipe.sourceDetails = scannedRecipe.sourceDetails
        recipe.introduction = scannedRecipe.introduction
        recipe.yield = scannedRecipe.yield
        recipe.servings = scannedRecipe.servings
        recipe.rating = scannedRecipe.rating
        recipe.difficulty = scannedRecipe.difficulty
        recipe.preparationTimes = scannedRecipe.preparationTimes
        recipe.notes = scannedRecipe.notes
        recipe.nutrition = scannedRecipe.nutrition
        recipe.lastModifiedDate = Date()
        
        // Convert structured ingredients to text
        if !scannedRecipe.ingredients.isEmpty {
            ingredientsText = scannedRecipe.ingredients.map { $0.text }.joined(separator: "\n")
        }
        
        // Convert structured directions to text
        if !scannedRecipe.directions.isEmpty {
            directionsText = scannedRecipe.directions.map { $0.text }.joined(separator: "\n\n")
        }
        
        logger.info("Successfully populated recipe with \(scannedRecipe.ingredients.count) ingredients and \(scannedRecipe.directions.count) directions")
    }
    
    // MARK: - Text Extraction Methods
    func extractTextToField(_ text: String, field: RecipeField) {
        let cleanText = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleanText.isEmpty else { 
            logger.warning("Empty text provided for \(field.rawValue)")
            return 
        }
        
        logger.info("Extracting text to \(field.rawValue): \(String(cleanText.prefix(100)))")
        
        switch field {
        case .name:
            recipe.name = cleanText
        case .source:
            recipe.source = cleanText
        case .sourceDetails:
            recipe.sourceDetails = cleanText
        case .servings:
            // Try to extract numeric value
            if let servings = Int(cleanText.filter { $0.isNumber }) {
                recipe.servings = servings
            }
        case .yield:
            recipe.yield = cleanText
        case .introduction:
            recipe.introduction = cleanText
        case .ingredients:
            appendToIngredientsText(cleanText)
        case .directions:
            appendToDirectionsText(cleanText)
        }
        
        logger.info("Successfully extracted text to \(field.rawValue): \(String(cleanText.prefix(100)))")
        
    }
    
    private func appendToIngredientsText(_ text: String) {
        if !ingredientsText.isEmpty {
            ingredientsText += "\n"
        }
        ingredientsText += text
    }
    
    private func appendToDirectionsText(_ text: String) {
        if !directionsText.isEmpty {
            directionsText += "\n"
        }
        directionsText += text
    }
    
    // MARK: - URL Navigation
    func navigateToURL(_ url: String) {
        var urlString = url.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Don't navigate if URL is empty or the same as current
        guard !urlString.isEmpty && urlString != currentURL else { return }
        
        // Add https:// if no protocol specified
        if !urlString.hasPrefix("http://") && !urlString.hasPrefix("https://") {
            urlString = "https://" + urlString
        }
        
        // Only update if the normalized URL is different
        if urlString != currentURL {
            currentURL = urlString
        }
    }
    
    func refreshCurrentPage() {
        // This will be handled by the web view
    }
    
    // MARK: - Helper Methods
    func updateNavigationState(canGoBack: Bool, canGoForward: Bool, isLoading: Bool) {
        self.canGoBack = canGoBack
        self.canGoForward = canGoForward
        self.isLoading = isLoading
    }
}

// MARK: - Recipe Field Enum
enum RecipeField: String, CaseIterable {
    case name = "Recipe Name"
    case source = "Source"
    case sourceDetails = "Source Details"
    case servings = "Servings"
    case yield = "Yield"
    case introduction = "Introduction"
    case ingredients = "Ingredients"
    case directions = "Directions"
    
    var shortcutKey: String {
        switch self {
        case .name: return "1"
        case .source: return "2"
        case .sourceDetails: return "3"
        case .servings: return "4"
        case .yield: return "7"
        case .introduction: return "8"
        case .ingredients: return "5"
        case .directions: return "6"
        }
    }
} 
