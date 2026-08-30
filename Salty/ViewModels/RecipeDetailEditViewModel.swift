//
//  RecipeDetailEditViewModel.swift
//  Salty
//
//  Created by Robert on 7/9/25.
//

import Foundation
import OSLog
import SQLiteData
import UUIDV7
import SaltyCore

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
    
    // MARK: - Category State
    var selectedCategoryIDs: Set<String> = []
    
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
    var showingEditVariationsSheet = false
    var showingNutritionEditSheet = false
    var showingScanTextSheet = false
    var scanTextTarget: ScanTextTarget = .ingredients
    var showingCancelAlert = false
    var showingSaveErrorAlert = false
    var saveErrorMessage: String?
    
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
                   !recipe.ingredients.isEmpty || !recipe.directions.isEmpty || !recipe.notes.isEmpty || !recipe.variations.isEmpty
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
    /// Saves the recipe and its category relationships. Returns `true` on success;
    /// on failure, sets `showingSaveErrorAlert` so the view can inform the user.
    @discardableResult
    func saveRecipe() async -> Bool {
        recipe.lastModifiedDate = Date()
        // Snapshot main-actor state into locals: the async write closure is @Sendable and runs
        // off the main actor, so it must not touch `self`.
        let recipeToSave = recipe
        let isNew = isNewRecipe
        let categoryIDs = selectedCategoryIDs
        do {
            try await database.write { db in
                if isNew {
                    // Insert new recipe
                    try Recipe.insert { recipeToSave }.execute(db)
                } else {
                    // Update existing recipe
                    try Recipe.update(recipeToSave).execute(db)
                }

                // Handle category relationships
                if !categoryIDs.isEmpty {
                    // Remove existing category relationships
                    try RecipeCategory
                        .where { $0.recipeId.eq(recipeToSave.id) }
                        .delete()
                        .execute(db)

                    // Add new category relationships
                    for categoryId in categoryIDs {
                        let recipeCategory = RecipeCategory(
                            id: UUIDV7().uuidString,
                            recipeId: recipeToSave.id,
                            categoryId: categoryId
                        )
                        try RecipeCategory.insertIfAbsent(recipeCategory, in: db)
                    }
                }
            }

            // Handle successful save of new recipe
            if isNew {
                onNewRecipeSaved?(recipeToSave.id)
            }

            // After successful save, this is no longer a new recipe
            isNewRecipe = false
            originalRecipe = recipeToSave
            return true

        } catch {
            logger.error("Error saving recipe: \(error)")
            saveErrorMessage = error.localizedDescription
            showingSaveErrorAlert = true
            return false
        }
    }
    
    // MARK: - Tag Management
    
    func addTag(_ tagName: String) async {
        let trimmedName = tagName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        let recipeId = recipe.id
        do {
            // Check if tag already exists
            let existingTag = try await database.read { db in
                try Tag
                    .where { $0.name.collate(.nocase).eq(trimmedName.collate(.nocase)) }
                    .fetchOne(db)
            }

            let tagToUse: Tag
            if let existing = existingTag {
                tagToUse = existing
            } else {
                // Create new tag
                let newTag = Tag(id: UUIDV7().uuidString, name: trimmedName, lastModifiedDate: Date())
                try await database.write { db in
                    try Tag.insert { newTag }.execute(db)
                }
                tagToUse = newTag
            }

            // Add tag to recipe unless it already carries it
            let recipeTag = RecipeTag(id: UUIDV7().uuidString, recipeId: recipeId, tagId: tagToUse.id)
            let added = try await database.write { db -> Bool in
                guard try RecipeTag.insertIfAbsent(recipeTag, in: db) else { return false }
                try Recipe.touchLastModified(recipeId: recipeId, in: db)
                return true
            }
            if added {
                recipe.lastModifiedDate = Date()
            }
        } catch {
            logger.error("Error adding tag: \(error)")
        }
    }

    func removeTag(_ tagName: String) async {
        let recipeId = recipe.id
        do {
            // Find the tag
            let tag = try await database.read { db in
                try Tag
                    .where { $0.name.collate(.nocase).eq(tagName.collate(.nocase)) }
                    .fetchOne(db)
            }

            guard let tag = tag else {
                logger.warning("Tag '\(tagName)' not found")
                return
            }

            // Remove the recipe-tag association
            try await database.write { db in
                try RecipeTag
                    .where { $0.recipeId.eq(recipeId) && $0.tagId.eq(tag.id) }
                    .delete()
                    .execute(db)
                try Recipe.touchLastModified(recipeId: recipeId, in: db)
            }
            recipe.lastModifiedDate = Date()

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
                try Recipe
                    .where { $0.id.eq(recipe.id) }
                    .fetchOne(db)
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

