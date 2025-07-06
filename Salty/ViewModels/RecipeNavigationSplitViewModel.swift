//
//  RecipeNavigationSplitViewModel.swift
//  Salty
//
//  Created by Robert on 7/3/25.
//

import Foundation
import OSLog
import SharingGRDB

@Observable
@MainActor
class RecipeNavigationSplitViewModel {
    // MARK: - Constants
    let allRecipesID: String = "0"
    private let logger = Logger(subsystem: "Salty", category: "Database")
    
    // MARK: - Dependencies
    @ObservationIgnored
    @Dependency(\.defaultDatabase) private var database
    
    // MARK: - Data (using SharingGRDB property wrappers)
    @ObservationIgnored
    @FetchAll var recipes: [Recipe]
    @ObservationIgnored
    @FetchAll var categories: [Category]
    
    // MARK: - State
    var searchString = ""
    var selectedSidebarItemId: String?
    var selectedRecipeIDs = Set<String>()
    
    var filteredRecipes: [Recipe] {
        var recipesToFilter: [Recipe]
        
        if selectedSidebarItemId == allRecipesID {
            recipesToFilter = recipes
        } else if let categoryId = selectedSidebarItemId,
                  let category = categories.first(where: { $0.id == categoryId }) {
            // Filter recipes for the selected category
            do {
                let recipeIds = try database.read { db in
                    try RecipeCategory
                        .filter(Column("categoryId") == category.id)
                        .fetchAll(db)
                        .map { $0.recipeId }
                }
                
                recipesToFilter = recipes.filter { recipe in
                    recipeIds.contains(recipe.id)
                }
            } catch {
                recipesToFilter = []
            }
        } else {
            recipesToFilter = []
        }
        
        // Apply search filter if search string is not empty
        if !searchString.isEmpty {
            let normalizedSearch = searchString
                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                .trimmingCharacters(in: .whitespacesAndNewlines)
            
            recipesToFilter = recipesToFilter.filter { recipe in
                let normalizedName = recipe.name
                    .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
                
                return normalizedName.contains(normalizedSearch)
            }
        }
        
        return recipesToFilter
    }
    
    var navigationTitle: String {
        if selectedSidebarItemId == allRecipesID {
            return "Recipes"
        } else if let categoryId = selectedSidebarItemId,
                  let category = categories.first(where: { $0.id == categoryId }) {
            return category.name
        } else {
            return "Recipes"
        }
    }
    
    // MARK: - Public Methods
    func addNewRecipe() {
        try? database.write { db in
            let newRecipe = Recipe(
                id: UUID().uuidString,
                name: "New Recipe",
                createdDate: Date(),
                lastModifiedDate: Date(),
                lastPrepared: Date(timeIntervalSinceNow: 0-60*24*45),
                isFavorite: false,
                wantToMake: false
            )
            try? newRecipe.insert(db)
        }
    }
    
    func deleteSelectedRecipes() {
        do {
            let _ = try database.write { db in
                try Recipe
                    .filter(selectedRecipeIDs.contains(Column("id")))
                    .deleteAll(db)
            }
            selectedRecipeIDs.removeAll()
        } catch {
            logger.error("Error deleting recipes: \(error)")
        }
    }
    
    func deleteRecipe(id: String) {
        do {
            let _ = try database.write { db in
                try Recipe
                    .filter(Column("id") == id)
                    .deleteAll(db)
            }
        } catch {
            logger.error("Error deleting recipe \(id): \(error)")
        }
    }
    
    func recipeToEdit(recipeId: String?) -> Recipe? {
        guard let recipeId = recipeId else { return nil }
        return recipes.first(where: { $0.id == recipeId })
    }
}

// MARK: - Preview ViewModel

/// A preview-specific ViewModel that doesn't use database dependencies
@Observable
@MainActor
class PreviewRecipeNavigationSplitViewModel: RecipeNavigationSplitViewModel {
    // MARK: - Preview Data
    private let previewRecipes: [Recipe]
    private let previewCategories: [Category]
    
    // MARK: - Override @FetchAll properties for preview
    override var recipes: [Recipe] { previewRecipes }
    override var categories: [Category] { previewCategories }
    
    // MARK: - Initialization
    init(previewData: (recipes: [Recipe], categories: [Category])) {
        self.previewRecipes = previewData.recipes
        self.previewCategories = previewData.categories
        super.init()
    }
    
    // MARK: - Override database-dependent methods
    override func addNewRecipe() {
        // No-op for preview
    }
    
    override func deleteSelectedRecipes() {
        // No-op for preview
    }
    
    override func deleteRecipe(id: String) {
        // No-op for preview
    }
}
