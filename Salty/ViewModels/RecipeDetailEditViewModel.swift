//
//  RecipeDetailEditViewModel.swift
//  Salty
//
//  Created by Robert on 7/9/25.
//

import Foundation
import OSLog
import SharingGRDB

@Observable
@MainActor
class RecipeDetailEditViewModel {
    private let logger = Logger(subsystem: "Salty", category: "Database")
    
    @ObservationIgnored
    @Dependency(\.defaultDatabase) private var database
    
    @ObservationIgnored
    @FetchAll(#sql("SELECT \(Course.columns) FROM \(Course.self) ORDER BY \(Course.name) COLLATE NOCASE"))
    var courses: [Course]
    
    @ObservationIgnored
    @FetchAll(#sql("SELECT \(Tag.columns) FROM \(Tag.self) ORDER BY \(Tag.name) COLLATE NOCASE"))
    var allTags: [Tag]
    
    // MARK: - State
    var recipe: Recipe
    var originalRecipe: Recipe
    var isNewRecipe: Bool
    var onNewRecipeSaved: ((String) -> Void)?
    
    // Cache for recipe tags
    private var recipeTags: [Tag] = []
   
    // MARK: - Sheet States
    // May want to name more generically in future, or somehow accomodate mobile if do navigation instead of popovers/sheets?
    var showingEditCategoriesSheet = false
    var showingEditIngredientsSheet = false
    var showingBulkEditIngredientsSheet = false
    var showingEditDirectionsSheet = false
    var showingBulkEditDirectionsSheet = false
    var showingEditPreparationTimes = false
    var showingEditNotesSheet = false
    var showingNutritionEditSheet = false
    var showingScanTextSheet = false
    var scanTextTarget: ScanTextTarget = .ingredients
    var showingCancelAlert = false
    
    enum ScanTextTarget: String, CaseIterable {
        case introduction = "Introduction"
        case ingredients = "Ingredients"
        case directions = "Directions"
    }
    
    // MARK: - Computed Properties
    var hasUnsavedChanges: Bool {
        if isNewRecipe {
            // New recipes are considered to have unsaved changes if they have meaningful content
            return !recipe.name.isEmpty || !recipe.source.isEmpty || !recipe.introduction.isEmpty ||
                   !recipe.ingredients.isEmpty || !recipe.directions.isEmpty || !recipe.notes.isEmpty
        } else {
            // Existing recipes have unsaved changes if they differ from the original
            return recipe != originalRecipe
        }
    }
    
    var sortedTags: [String] {
        // TODO: Implement tag fetching
        return []
    }
    
    var hasTags: Bool {
        // TODO: Implement tag checking
        return false
    }
    
    // MARK: - Initialization
    init(recipe: Recipe, isNewRecipe: Bool = false, onNewRecipeSaved: ((String) -> Void)? = nil) {
        self.recipe = recipe
        self.originalRecipe = recipe
        self.isNewRecipe = isNewRecipe
        self.onNewRecipeSaved = onNewRecipeSaved
    }
    
    // MARK: - Public Methods
    func saveRecipe() {
        recipe.lastModifiedDate = Date()
        do {
            try database.write { db in
                if isNewRecipe {
                    // Insert new recipe
                    try recipe.insert(db)
                    logger.info("New recipe inserted successfully: \(self.recipe.id)")
                } else {
                    // Update existing recipe
                    try recipe.update(db)
                    logger.info("Recipe updated successfully: \(self.recipe.id)")
                }
            }
            
            // Handle successful save of new recipe
            if isNewRecipe {
                onNewRecipeSaved?(recipe.id)
            }
            
            // After successful save, this is no longer a new recipe
            isNewRecipe = false
            originalRecipe = recipe
            
        } catch {
            logger.error("Error saving recipe: \(error)")
        }
    }
    
    // MARK: - Tag Management
    
    // TODO: Implement tag management similar to categories
    // For now, just provide basic structure
    func addTag(_ tagName: String) {
        // TODO: Implement tag addition
        logger.info("Tag addition not yet implemented")
    }
    
    func removeTag(_ tagName: String) {
        // TODO: Implement tag removal
        logger.info("Tag removal not yet implemented")
    }
    
    func discardChanges() {
        recipe = originalRecipe
    }
}

