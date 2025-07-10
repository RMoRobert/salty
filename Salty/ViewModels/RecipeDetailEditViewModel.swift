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
    // MARK: - Constants
    private let logger = Logger(subsystem: "Salty", category: "Database")
    
    // MARK: - Dependencies
    @ObservationIgnored
    @Dependency(\.defaultDatabase) private var database
    
    // MARK: - State
    var recipe: Recipe
    var originalRecipe: Recipe
    
    // MARK: - Sheet States
    // May want to name more generically in future, or somehow accomodate mobile if do navigation instead of popovers/sheets?
    var showingEditCategoriesSheet = false
    var showingEditIngredientsSheet = false
    var showingEditDirectionsSheet = false
    var showingEditPreparationTimes = false
    var showingEditNotesSheet = false
    var showingCancelAlert = false
    
    // MARK: - Computed Properties
    var hasUnsavedChanges: Bool {
        return recipe != originalRecipe
    }
    
    // MARK: - Initialization
    init(recipe: Recipe) {
        self.recipe = recipe
        self.originalRecipe = recipe
    }
    
    // MARK: - Public Methods
    func saveRecipe() {
        recipe.lastModifiedDate = Date()
        do {
            try database.write { db in
                try Recipe.upsert(Recipe.Draft(recipe))
                    .execute(db)
            }
            logger.info("Recipe saved successfully: \(self.recipe.id)")
        } catch {
            logger.error("Error saving recipe: \(error)")
        }
    }
    
    func discardChanges() {
        recipe = originalRecipe
    }
    
//    func resetToOriginal() {
//        recipe = originalRecipe
//    }
//    
//    func updateRecipe(_ updatedRecipe: Recipe) {
//        recipe = updatedRecipe
//    }
}

