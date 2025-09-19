//
//  RecipeNavigationSplitViewModel.swift
//  Salty
//
//  Created by Robert on 7/3/25.
//

import Foundation
import OSLog
import SharingGRDB

// MARK: - Notification Names

extension Notification.Name {
    static let exportSelectedRecipes = Notification.Name("exportSelectedRecipes")
    static let showImportFromFileSheet = Notification.Name("showImportFromFileSheet")
    static let showOpenDatabaseSheet = Notification.Name("showOpenDatabaseSheet")
    static let showCreateFromWebSheet = Notification.Name("showCreateFromWebSheet")
    static let sheetStateChanged = Notification.Name("sheetStateChanged")
}

@Observable
@MainActor
class RecipeNavigationSplitViewModel {
    var isNewLaunch = false // true if first launch of app, view should use to show reasonable default instead of blank-looking page on mobile
    
    init() {
        // Check if this is a new launch by looking for existing recipes
        // We'll set this properly after the database is loaded
    }
    
    /// Call this method after the database is loaded to set up the initial state
    func setupInitialState() {
        // Set default selection to "All Recipes" if currently nothing selected
        if selectedSidebarItemId == nil {
            selectedSidebarItemId = allRecipesID
        }
    }
    // MARK: - Constants
    let allRecipesID: String = "0"
    private let logger = Logger(subsystem: "Salty", category: "Database")
    
    // MARK: - Dependencies
    @ObservationIgnored
    @Dependency(\.defaultDatabase)
    private var database
    
    // MARK: - Data (using SharingGRDB property wrappers)
    @ObservationIgnored
    @FetchAll(#sql("SELECT \(Recipe.columns) FROM \(Recipe.self) ORDER BY \(Recipe.name) COLLATE NOCASE"))
    var recipes: [Recipe]
    
    @ObservationIgnored
    @FetchAll(#sql("SELECT \(Category.columns) FROM \(Category.self) ORDER BY \(Category.name) COLLATE NOCASE"))
    var categories: [Category]
            
    // MARK: - State
    var searchString = ""
    var selectedSidebarItemId: String?
    var selectedRecipeIDs = Set<String>()
    var isFavoritesFilterActive = false
    var showingEditSheet = false
    var recipeToEditID: String?
    var shouldScrollToNewRecipe = false
    var draftRecipe: Recipe?
    
    // Export-related state
    var showingExportSheet = false
    var exportData: Data?
    var exportFileName = ""
    var exportErrorMessage = ""
    var showingExportErrorAlert = false
    

    // TODO: Do more of this in database and not filtering afterwards
    // Consider also using "@Select" instead of retrieving entire recipe data for preview only
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
        
        if isFavoritesFilterActive == true {
            recipesToFilter = recipesToFilter.filter(\.self.isFavorite)
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
        let newRecipe = Recipe(
            id: UUID().uuidString,
            name: "New Recipe",
            createdDate: Date(),
            lastModifiedDate: Date(),
            isFavorite: false,
            wantToMake: false
        )
        
        // Store as draft - don't save to database yet
        draftRecipe = newRecipe
        recipeToEditID = newRecipe.id
        showingEditSheet = true
        
        logger.info("New recipe draft created: \(newRecipe.id)")
    }
    
    func deleteSelectedRecipes() {
        // TODO: Delete images or schedule cleanup methods to remove image
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
        // TODO: Delete images or schedule cleanup methods to remove image
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
        
        // Check if this is a draft recipe first
        if let draftRecipe = draftRecipe, draftRecipe.id == recipeId {
            return draftRecipe
        }
        
        // Otherwise, find existing recipe
        return recipes.first(where: { $0.id == recipeId })
    }
    
    func clearDraftRecipe() {
        draftRecipe = nil
    }
    
    func isDraftRecipe(_ recipeId: String?) -> Bool {
        guard let recipeId = recipeId else { return false }
        return draftRecipe?.id == recipeId
    }
    
    func handleNewRecipeSaved(recipeId: String) {
        // Switch to "All Recipes" view so the new recipe will be visible
        selectedSidebarItemId = allRecipesID
        
        // Select the newly saved recipe and scroll to it
        selectedRecipeIDs = [recipeId]
        shouldScrollToNewRecipe = true
        
        // Clear the draft since it's now persisted
        draftRecipe = nil
        
        logger.info("New recipe saved and selected: \(recipeId)")
    }
    
    // MARK: - Export Methods
    
    /// Exports a single recipe to JSON format
    /// - Parameter recipeId: The ID of the recipe to export
    func exportRecipe(_ recipeId: String) {
        Task {
            do {
                guard let recipe = recipes.first(where: { $0.id == recipeId }) else {
                    await MainActor.run {
                        exportErrorMessage = "Recipe not found"
                        showingExportErrorAlert = true
                    }
                    return
                }
                
                let exportRecipe = try SaltyRecipeExport.fromRecipe(recipe, database: database)
                let jsonData = try exportRecipe.toJSONData()
                
                await MainActor.run {
                    exportData = jsonData
                    exportFileName = "\(recipe.name).saltyRecipe"
                    showingExportSheet = true
                }
            } catch {
                await MainActor.run {
                    exportErrorMessage = "Export failed: \(error.localizedDescription)"
                    showingExportErrorAlert = true
                }
            }
        }
    }
    
    /// Exports multiple selected recipes to JSON format
    func exportSelectedRecipes() {
        Task {
            do {
                let recipesToExport = recipes.filter { selectedRecipeIDs.contains($0.id) }
                
                if recipesToExport.isEmpty {
                    await MainActor.run {
                        exportErrorMessage = "No recipes selected for export"
                        showingExportErrorAlert = true
                    }
                    return
                }
                
                let exportRecipes = try recipesToExport.map { recipe in
                    try SaltyRecipeExport.fromRecipe(recipe, database: database)
                }
                
                let encoder = JSONEncoder()
                encoder.dateEncodingStrategy = .iso8601
                // This can be useful for testing:
                //encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
                let jsonData = try encoder.encode(exportRecipes)
                
                await MainActor.run {
                    exportData = jsonData
                    let count = recipesToExport.count
                    exportFileName = count == 1 ? "\(recipesToExport.first!.name).saltyRecipe" : "\(count)_recipes.saltyRecipe"
                    showingExportSheet = true
                }
            } catch {
                await MainActor.run {
                    exportErrorMessage = "Export failed: \(error.localizedDescription)"
                    showingExportErrorAlert = true
                }
            }
        }
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
