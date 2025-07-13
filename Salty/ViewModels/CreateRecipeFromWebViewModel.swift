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
    var currentURL: String = "https://www.google.com"
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
    var lastExtractedField: RecipeField?
    
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
        
        logger.info("🔄 Extracting text to \(field.rawValue): \(String(cleanText.prefix(100)))")
        
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
        
        logger.info("✅ Successfully extracted text to \(field.rawValue): \(String(cleanText.prefix(100)))")
        
        // Update the last extracted field for UI feedback
        lastExtractedField = field
        
        // Clear the feedback after a short delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
            self.lastExtractedField = nil
        }
    }
    
    private func appendToIngredients(_ text: String) {
        let lines = text.components(separatedBy: .newlines)
        for line in lines {
            let cleanLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleanLine.isEmpty {
                let ingredient = Ingredient(
                    id: UUID().uuidString,
                    isHeading: false,
                    isMain: false,
                    text: cleanLine
                )
                recipe.ingredients.append(ingredient)
            }
        }
    }
    
    private func appendToDirections(_ text: String) {
        let lines = text.components(separatedBy: .newlines)
        for line in lines {
            let cleanLine = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if !cleanLine.isEmpty {
                let direction = Direction(
                    id: UUID().uuidString,
                    isHeading: false,
                    text: cleanLine
                )
                recipe.directions.append(direction)
            }
        }
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
