//
//  RecipeDetailViewModel.swift
//  Salty
//
//  Created by Robert on 8/6/25.
//

import Foundation
import OSLog
import SQLiteData
import SaltyCore

@Observable
@MainActor
class RecipeDetailViewModel {
    private let logger = Logger(subsystem: "Salty", category: "App")
    
    @ObservationIgnored
    @Dependency(\.defaultDatabase) private var database
    
    // MARK: - State
    let recipeId: String
    var showingFullImage = false
    /// iOS/iPadOS only — macOS opens Chef View in its own window instead of a cover.
    var isChefViewPresented = false

    /// Temporary ingredient scale for detail view only. Stored as a fraction for `.percent` formatting (1.0 = 100%, 2.0 = 200%).
    var ingredientScalePercent = 1.0
    var isIngredientScalePopoverShowing = false
    var isSavingScaledRecipe = false
    var scaledRecipeSaveErrorMessage: String?
    
    @ObservationIgnored
    private let onScaledRecipeSaved: ((String) -> Void)?
    
    @ObservationIgnored
    @FetchOne var recipe: Recipe?
    
    #if !os(macOS)
    var isTitleVisible: Bool = true
    #else
    var isTitleVisible = false
    #endif
    
    @ObservationIgnored
    @FetchAll(#sql("SELECT \(Course.columns) FROM \(Course.self) ORDER BY \(Course.name) COLLATE NOCASE"))
    var courses: [Course]
    
    @ObservationIgnored
    @FetchAll(#sql("SELECT \(Category.columns) FROM \(Category.self) ORDER BY \(Category.name) COLLATE NOCASE"))
    var categories: [Category]
    
    @ObservationIgnored
    @FetchAll(#sql("SELECT \(Tag.columns) FROM \(Tag.self) ORDER BY \(Tag.name) COLLATE NOCASE"))
    var tags: [Tag]
    
    @ObservationIgnored
    @FetchAll(#sql("SELECT \(RecipeTag.columns) FROM \(RecipeTag.self) ORDER BY \(RecipeTag.id)"))
    var allRecipeTags: [RecipeTag]

    @ObservationIgnored
    @FetchAll(#sql("SELECT \(RecipeCategory.columns) FROM \(RecipeCategory.self) ORDER BY \(RecipeCategory.id)"))
    var allRecipeCategories: [RecipeCategory]

    // MARK: - Computed Properties
    #if !os(macOS)
    var shouldShowNavigationTitle: Bool {
        // Show navigation title when the recipe title is no longer visible
        return !isTitleVisible
    }
    #endif
    
    var courseName: String? {
        guard let recipe = recipe, let courseId = recipe.courseId else { return nil }
        return courses.first { $0.id == courseId }?.name
    }
    
    var recipeCategories: [Category] {
        guard let recipe = recipe else { return [] }
        // Derive from the observed @FetchAll join table (no synchronous DB read on the main thread),
        // mirroring how `recipeTags` is computed.
        let recipeCategoryIds = allRecipeCategories.filter { $0.recipeId == recipe.id }.map { $0.categoryId }
        return categories.filter { recipeCategoryIds.contains($0.id) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    
    var recipeTags: [Tag] {
        guard let recipe = recipe else { return [] }
        let recipeTagIds = allRecipeTags.filter { $0.recipeId == recipe.id }.map { $0.tagId }
        return tags.filter { recipeTagIds.contains($0.id) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    
    /// Multiplier applied to ingredient quantities (same as `ingredientScalePercent`).
    var ingredientScaleFactor: Double { ingredientScalePercent }
    
    var isIngredientScaleActive: Bool {
        abs(ingredientScalePercent - 1.0) > 0.001
    }
    
    /// Display-only percent number for footnotes and saved recipe names (e.g. `50`, `200`).
    var ingredientScalePercentLabel: String {
        let displayPercent = ingredientScalePercent * 100
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: NSNumber(value: displayPercent)) ?? "\(displayPercent)"
    }
    
    var ingredientScaleDirectionsFootnote: String {
        "Ingredients scaled to \(ingredientScalePercentLabel)%. Amounts and times mentioned in directions may refer to quantity in orignal recipe. Please verify before use."
    }
    
    func scaledIngredientDisplay(_ ingredient: Ingredient) -> IngredientScaler.DisplayParts {
        IngredientScaler.displayParts(for: ingredient, scaleFactor: ingredientScaleFactor)
    }
    
    func resetIngredientScale() {
        ingredientScalePercent = 1.0
    }
    
    /// - Parameter targetFactor: Scale as a fraction (e.g. `0.5` for half, `2.0` for double).
    func isIngredientScaleNear(_ targetFactor: Double, tolerance: Double = 0.01) -> Bool {
        abs(ingredientScalePercent - targetFactor) <= tolerance
    }
    
    func saveAsScaledRecipe() async {
        guard let source = recipe, isIngredientScaleActive, !isSavingScaledRecipe else { return }

        isSavingScaledRecipe = true
        scaledRecipeSaveErrorMessage = nil

        // Snapshot main-actor state before the off-actor duplicate work.
        let categoryIds = recipeCategories.map(\.id)
        let tagIds = recipeTags.map(\.id)
        let options = RecipeDuplicator.Options(
            ingredientScaleFactor: ingredientScaleFactor,
            scalePercentLabel: ingredientScalePercentLabel,
            sourceRecipeName: source.name
        )

        do {
            let newId = try await RecipeDuplicator.duplicate(
                source: source,
                database: database,
                categoryIds: categoryIds,
                tagIds: tagIds,
                options: options
            )
            isIngredientScalePopoverShowing = false
            onScaledRecipeSaved?(newId)
        } catch {
            logger.error("Failed to save scaled recipe copy: \(error)")
            scaledRecipeSaveErrorMessage = error.localizedDescription
        }

        isSavingScaledRecipe = false
    }
    
    // MARK: - Initialization
    init(recipe: Recipe, onScaledRecipeSaved: ((String) -> Void)? = nil) {
        self.recipeId = recipe.id
        self.onScaledRecipeSaved = onScaledRecipeSaved
        self._recipe = FetchOne(
            wrappedValue: recipe, 
            #sql("SELECT \(Recipe.columns) FROM \(Recipe.self) WHERE \(Recipe.id) = \(bind: recipe.id)")
        )
    }
    
    init(recipeId: String, onScaledRecipeSaved: ((String) -> Void)? = nil) {
        self.recipeId = recipeId
        self.onScaledRecipeSaved = onScaledRecipeSaved
        self._recipe = FetchOne(
            wrappedValue: nil as Recipe?,
            #sql("SELECT \(Recipe.columns) FROM \(Recipe.self) WHERE \(Recipe.id) = \(bind: recipeId)")
        )
    }
    
    func showFullImage() {
        showingFullImage = true
    }
    
    func hideFullImage() {
        showingFullImage = false
    }
}
