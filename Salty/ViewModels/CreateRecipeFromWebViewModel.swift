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
    
    // MARK: - Web Browser State
    var currentURL: String = "https://github.com/smeckledorfed/Recipes-Master-List?tab=readme-ov-file#community"  // TODO: Change to sensible default
    var canGoBack = false
    var canGoForward = false
    var isLoading = false
    
    // MARK: - UI State
    var showingCategoriesSheet = false
    var showingPreparationTimesSheet = false
    var showingImageEditSheet = false
    var showingNotesSheet = false
    var showingBulkEditIngredientsSheet = false
    var showingBulkEditDirectionsSheet = false
    var showingSaveAlert = false
    var showingCancelAlert = false
    
    // MARK: - Computed Properties
    var hasRecipeData: Bool {
        return !recipe.name.isEmpty || 
               !recipe.source.isEmpty || 
               !recipe.sourceDetails.isEmpty || 
               !recipe.introduction.isEmpty ||
               !recipe.ingredients.isEmpty ||
               !recipe.directions.isEmpty ||
               !recipe.notes.isEmpty
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

    
    func resetRecipe() {
        recipe = Recipe(
            id: UUID().uuidString,
            name: "",
            createdDate: Date(),
            lastModifiedDate: Date()
        )
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
            appendToIngredients(cleanText)
        case .directions:
            appendToDirections(cleanText)
        }
        
        logger.info("Successfully extracted text to \(field.rawValue): \(String(cleanText.prefix(100)))")
        
    }
    
    private func appendToIngredients(_ text: String) {
        // Use the simple parsing for web extraction (no heading detection)
        let newIngredients = IngredientTextParser.parseIngredientsSimple(from: text)
        recipe.ingredients.append(contentsOf: newIngredients)
    }
    
    private func appendToDirections(_ text: String) {
        // Use the simple parsing for web extraction (no heading detection)
        let newDirections = DirectionTextParser.parseDirectionsSimple(from: text)
        recipe.directions.append(contentsOf: newDirections)
    }
    
    // MARK: - URL Navigation
    func navigateToURL(_ url: String) {
        var urlString = url
        if !urlString.hasPrefix("http://") && !urlString.hasPrefix("https://") {
            urlString = "https://" + urlString
        }
        currentURL = urlString
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
