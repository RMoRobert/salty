//
//  RecipeDetailViewModel.swift
//  Salty
//
//  Created by Robert on 8/6/25.
//

import Foundation
import OSLog
import SQLiteData

@Observable
@MainActor
class RecipeDetailViewModel {
    private let logger = Logger(subsystem: "Salty", category: "App")
    
    @ObservationIgnored
    @Dependency(\.defaultDatabase) private var database
    
    // MARK: - State
    let recipeId: String
    var showingFullImage = false
    
    /// Temporary ingredient scale for detail view only (100 = original recipe).
    var ingredientScalePercent: Double = 100
    var isIngredientScalePopoverShowing = false
    
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
        do {
            let recipeCategoryIds = try database.read { db in
                try RecipeCategory
                    .where { $0.recipeId.eq(recipe.id) }
                    .fetchAll(db)
                    .map { $0.categoryId }
            }
            return categories.filter { recipeCategoryIds.contains($0.id) }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        } catch {
            logger.error("Error loading recipe categories: \(error)")
            return []
        }
    }
    
    var recipeTags: [Tag] {
        guard let recipe = recipe else { return [] }
        let recipeTagIds = allRecipeTags.filter { $0.recipeId == recipe.id }.map { $0.tagId }
        return tags.filter { recipeTagIds.contains($0.id) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }
    
    var ingredientScaleFactor: Double { ingredientScalePercent / 100 }
    
    var isIngredientScaleActive: Bool {
        abs(ingredientScalePercent - 100) > 0.001
    }
    
    var ingredientScalePercentLabel: String {
        let formatter = NumberFormatter()
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 0
        formatter.maximumFractionDigits = 2
        formatter.locale = Locale(identifier: "en_US_POSIX")
        return formatter.string(from: NSNumber(value: ingredientScalePercent)) ?? "\(ingredientScalePercent)"
    }
    
    var ingredientScaleDirectionsFootnote: String {
        "Ingredients scaled to \(ingredientScalePercentLabel)%. Amounts and times mentioned in directions may refer to quantity in orignal recipe. Please verify before use."
    }
    
    func scaledIngredientDisplay(_ ingredient: Ingredient) -> IngredientScaler.DisplayParts {
        IngredientScaler.displayParts(for: ingredient, scaleFactor: ingredientScaleFactor)
    }
    
    func resetIngredientScale() {
        ingredientScalePercent = 100
    }
    
    // MARK: - Initialization
    init(recipe: Recipe) {
        self.recipeId = recipe.id
        self._recipe = FetchOne(
            wrappedValue: recipe, 
            #sql("SELECT \(Recipe.columns) FROM \(Recipe.self) WHERE \(Recipe.id) = \(bind: recipe.id)")
        )
    }
    
    init(recipeId: String) {
        self.recipeId = recipeId
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
