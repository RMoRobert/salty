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
    var allCourses: [Course]
    
    @ObservationIgnored
    @FetchAll(#sql("SELECT \(Category.columns) FROM \(Category.self) ORDER BY \(Category.name) COLLATE NOCASE"))
    var allCategories: [Category]
    
    @ObservationIgnored
    @FetchAll(#sql("SELECT \(RecipeCategory.columns) FROM \(RecipeCategory.self)"))
    var allRecipeCategories: [RecipeCategory]
    
    @ObservationIgnored
    @FetchAll(#sql("SELECT \(Tag.columns) FROM \(Tag.self) ORDER BY \(Tag.name) COLLATE NOCASE"))
    var allTags: [Tag]
    
    @ObservationIgnored
    @FetchAll(#sql("SELECT \(RecipeTag.columns) FROM \(RecipeTag.self)"))
    var allRecipeTags: [RecipeTag]
    
    // MARK: - State  
    var recipe: Recipe
    var originalRecipe: Recipe
    var isNewRecipe: Bool
    var onNewRecipeSaved: ((String) -> Void)?
    
    // Caches for tags and categories
    private var recipeTags: [Tag] = []
    private var recipeCategories: [Category] = []
   
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
        
    var sortedCategories: [String] {
        let recipeCategoryIds = allRecipeCategories.filter { $0.recipeId == recipe.id }.map { $0.categoryId }
        return allCategories.filter { recipeCategoryIds.contains($0.id) }
            .map { $0.name }
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }
    
    var hasCategories: Bool {
        !sortedCategories.isEmpty
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
            let _ = try database.write { db in
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
    
    private func refreshRecipeFromDatabase() {
        do {
            if let refreshedRecipe = try database.read({ db in
                try Recipe.fetchOne(db, key: recipe.id)
            }) {
                recipe = refreshedRecipe
                originalRecipe = refreshedRecipe
            }
        } catch {
            logger.error("Error refreshing recipe from database: \(error)")
        }
    }
    

    

    

   
    var nutritionSummary: String? {
        guard let nutrition = recipe.nutrition else { return nil }

        var parts: [String] = []

        if let servingSize = nutrition.servingSize {
            parts.append("Serving Size: \(servingSize)")
        }
        if let calories = nutrition.calories {
            parts.append("Calories: \(calories.formatted())")
        }
        if let fat = nutrition.fat {
            parts.append("Total Fat: \(fat.formatted())g")
        }
        if let saturatedFat = nutrition.saturatedFat {
            parts.append("Saturated Fat: \(saturatedFat.formatted())g")
        }
        if let transFat = nutrition.transFat {
            parts.append("Trans Fat: \(transFat.formatted())g")
        }
        if let cholesterol = nutrition.cholesterol {
            parts.append("Cholesterol: \(cholesterol.formatted())mg")
        }
        if let sodium = nutrition.sodium {
            parts.append("Sodium: \(sodium.formatted())mg")
        }
        if let carbs = nutrition.carbohydrates {
            parts.append("Total Carbs: \(carbs.formatted())g")
        }
        if let fiber = nutrition.fiber {
            parts.append("Fiber: \(fiber.formatted())g")
        }
        if let sugar = nutrition.sugar {
            parts.append("Sugars: \(sugar.formatted())g")
        }
        if let protein = nutrition.protein {
            parts.append("Protein: \(protein.formatted())g")
        }

        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

}

