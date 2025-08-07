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
    
    @ObservationIgnored
    @FetchAll(#sql("SELECT \(RecipeTag.columns) FROM \(RecipeTag.self) ORDER BY \(RecipeTag.id)"))
    var allRecipeTags: [RecipeTag]
    
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
        let recipeTagIds = allRecipeTags.filter { $0.recipeId == recipe.id }.map { $0.tagId }
        return allTags.filter { recipeTagIds.contains($0.id) }
            .map { $0.name }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
    
    var hasTags: Bool {
        !sortedTags.isEmpty
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
    
    func addTag(_ tagName: String) {
        let trimmedName = tagName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        
        do {
            // Check if tag already exists
            let existingTag = try database.read { db in
                try Tag
                    .filter(sql: "LOWER(name) = LOWER(?)", arguments: [trimmedName])
                    .fetchOne(db)
            }
            
            let tagToUse: Tag
            if let existing = existingTag {
                tagToUse = existing
            } else {
                // Create new tag
                tagToUse = Tag(id: UUID().uuidString, name: trimmedName)
                try database.write { db in
                    try tagToUse.insert(db)
                }
            }
            
            // Check if recipe already has this tag
            let existingRecipeTag = try database.read { db in
                try RecipeTag
                    .filter(RecipeTag.Columns.recipeId == recipe.id && RecipeTag.Columns.tagId == tagToUse.id)
                    .fetchOne(db)
            }
            
            if existingRecipeTag == nil {
                // Add tag to recipe
                let recipeTag = RecipeTag(id: UUID().uuidString, recipeId: recipe.id, tagId: tagToUse.id)
                try database.write { db in
                    try recipeTag.insert(db)
                }
                logger.info("Tag '\(trimmedName)' added to recipe")
            }
        } catch {
            logger.error("Error adding tag: \(error)")
        }
    }
    
    func removeTag(_ tagName: String) {
        do {
            // Find the tag
            let tag = try database.read { db in
                try Tag
                    .filter(sql: "LOWER(name) = LOWER(?)", arguments: [tagName])
                    .fetchOne(db)
            }
            
            guard let tag = tag else {
                logger.warning("Tag '\(tagName)' not found")
                return
            }
            
            // Remove the recipe-tag association
            try database.write { db in
                try RecipeTag
                    .filter(RecipeTag.Columns.recipeId == recipe.id && RecipeTag.Columns.tagId == tag.id)
                    .deleteAll(db)
            }
            
            logger.info("Tag '\(tagName)' removed from recipe")
        } catch {
            logger.error("Error removing tag: \(error)")
        }
    }
    
    func discardChanges() {
        recipe = originalRecipe
    }
}

