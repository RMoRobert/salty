//
//  RecipeNavigationSplitViewModel.swift
//  Salty
//
//  Created by Robert on 7/3/25.
//

import Foundation
import OSLog
import SQLiteData

// MARK: - Notification Names

extension Notification.Name {
    static let exportSelectedRecipes = Notification.Name("exportSelectedRecipes")
    static let showImportFromFileSheet = Notification.Name("showImportFromFileSheet")
    static let showCreateFromWebSheet = Notification.Name("showCreateFromWebSheet")
    static let sheetStateChanged = Notification.Name("sheetStateChanged")
    static let showRecipeInfoInspector = Notification.Name("showRecipeInfoInspector")
    static let recipeSelectionChanged = Notification.Name("recipeSelectionChanged")
}

@Observable
@MainActor
class RecipeNavigationSplitViewModel {
    var isNewLaunch = false // true if first launch of app, view should use to show reasonable default instead of blank-looking page on mobile
    
    init() {
        // Check if this is a new launch by looking for existing recipes
        // We'll set this properly after the database is loaded
        
        // Initialize sort settings from UserDefaults (only if they exist, otherwise use defaults)
        if let rawValue = UserDefaults.standard.string(forKey: "recipeListSortOrder"),
           let setting = RecipeListSortOrderSetting(rawValue: rawValue) {
            recipeListSortOrder = setting
        }
        
        if let rawValue = UserDefaults.standard.string(forKey: "recipeListSortDirection"),
           let direction = RecipeListSortDirection(rawValue: rawValue) {
            recipeListSortDirection = direction
        }
        
        // Observe UserDefaults changes for sort settings (from menu updates)
        NotificationCenter.default.addObserver(
            forName: UserDefaults.didChangeNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            guard let self = self else { return }
            // Update stored properties if UserDefaults changed externally
            if let rawValue = UserDefaults.standard.string(forKey: "recipeListSortOrder"),
               let setting = RecipeListSortOrderSetting(rawValue: rawValue),
               setting != self.recipeListSortOrder {
                self.recipeListSortOrder = setting
            }
            
            if let rawValue = UserDefaults.standard.string(forKey: "recipeListSortDirection"),
               let direction = RecipeListSortDirection(rawValue: rawValue),
               direction != self.recipeListSortDirection {
                self.recipeListSortDirection = direction
            }
        }
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
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
    
    // MARK: - Data (using SQLiteData property wrappers)
    @ObservationIgnored
//    @FetchAll(#sql("SELECT \(Recipe.columns) FROM \(Recipe.self) ORDER BY \(Recipe.name) COLLATE NOCASE"))
//    var recipes: [Recipe]
    @FetchAll
    var recipes: [Recipe]
    
    @ObservationIgnored
    @FetchAll(#sql("SELECT \(Category.columns) FROM \(Category.self) ORDER BY \(Category.name) COLLATE NOCASE"))
    var categories: [Category]
            
    // MARK: - State
    var searchString = ""
    var selectedSidebarItemId: String?
    var selectedRecipeIDs = Set<String>()
    var isFavoritesFilterActive = false
    
    var recipeListSortOrder: RecipeListSortOrderSetting = .byName {
        didSet {
            // Only write to UserDefaults if the value in UserDefaults is different
            // This prevents redundant writes when syncing from external changes
            if UserDefaults.standard.string(forKey: "recipeListSortOrder") != recipeListSortOrder.rawValue {
                UserDefaults.standard.set(recipeListSortOrder.rawValue, forKey: "recipeListSortOrder")
            }
        }
    }
    
    var recipeListSortDirection: RecipeListSortDirection = .ascending {
        didSet {
            // Only write to UserDefaults if the value in UserDefaults is different
            // This prevents redundant writes when syncing from external changes
            if UserDefaults.standard.string(forKey: "recipeListSortDirection") != recipeListSortDirection.rawValue {
                UserDefaults.standard.set(recipeListSortDirection.rawValue, forKey: "recipeListSortDirection")
            }
        }
    }
    
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
    

//    // TODO: Do more of this in database and not filtering afterwards
//    // Consider also using "@Select" instead of retrieving entire recipe data for preview only
//    var filteredRecipes: [Recipe] {
//        var recipesToFilter: [Recipe]
//        
//        if selectedSidebarItemId == allRecipesID {
//            recipesToFilter = recipes
//        } else if let categoryId = selectedSidebarItemId,
//                  let category = categories.first(where: { $0.id == categoryId }) {
//            // Filter recipes for the selected category
//            do {
//                let recipeIds = try database.read { db in
//                    try RecipeCategory
//                        .where { $0.categoryId == category.id }
//                        .fetchAll(db)
//                        .map { $0.recipeId }
//                }
//                
//                recipesToFilter = recipes.filter { recipe in
//                    recipeIds.contains(recipe.id)
//                }
//            } catch {
//                recipesToFilter = []
//            }
//        } else {
//            recipesToFilter = []
//        }
//        
//        // Apply search filter if search string is not empty
//        if !searchString.isEmpty {
//            let normalizedSearch = searchString
//                .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
//                .trimmingCharacters(in: .whitespacesAndNewlines)
//            
//            recipesToFilter = recipesToFilter.filter { recipe in
//                let normalizedName = recipe.name
//                    .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
//                
//                return normalizedName.contains(normalizedSearch)
//            }
//        }
//        
//        if isFavoritesFilterActive == true {
//            recipesToFilter = recipesToFilter.filter(\.self.isFavorite)
//        }
//        
//        return recipesToFilter
//    }
    
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
    
    private func loadAllRecipesQuery(searchPattern: String?, includeFavorites: Bool, sortOrder: RecipeListSortOrderSetting, sortDirection: RecipeListSortDirection) async throws {
        // Build query using method chaining
        let searchPattern = searchPattern
        
        if let searchPattern = searchPattern, includeFavorites {
            // Query with search AND favorites
            try await $recipes.load(
                Recipe
                    .where {
                        #sql("\($0.name) COLLATE NOCASE LIKE \(bind: searchPattern)") && $0.isFavorite == true
                    }
                    .order {
                        switch (sortOrder, sortDirection) {
                        case (.byName, .ascending):
                            #sql("\($0.name) COLLATE NOCASE")
                        case (.byName, .descending):
                            #sql("\($0.name) COLLATE NOCASE DESC")
                        case (.bySource, .ascending):
                            #sql("\($0.source) COLLATE NOCASE")
                        case (.bySource, .descending):
                            #sql("\($0.source) COLLATE NOCASE DESC")
                        case (.byDateModified, .ascending):
                            $0.lastModifiedDate
                        case (.byDateModified, .descending):
                            $0.lastModifiedDate.desc()
                        case (.byDateCreated, .ascending):
                            $0.createdDate
                        case (.byDateCreated, .descending):
                            $0.createdDate.desc()
                        case (.byRating, .ascending):
                            $0.rating
                        case (.byRating, .descending):
                            $0.rating.desc()
                        case (.byDifficulty, .ascending):
                            $0.difficulty
                        case (.byDifficulty, .descending):
                            $0.difficulty.desc()
                        }
                    }
            )
        } else if let searchPattern = searchPattern {
            // Query with search only
            try await $recipes.load(
                Recipe
                    .where {
                        #sql("\($0.name) COLLATE NOCASE LIKE \(bind: searchPattern)")
                    }
                    .order {
                        switch (sortOrder, sortDirection) {
                        case (.byName, .ascending):
                            #sql("\($0.name) COLLATE NOCASE")
                        case (.byName, .descending):
                            #sql("\($0.name) COLLATE NOCASE DESC")
                        case (.bySource, .ascending):
                            #sql("\($0.source) COLLATE NOCASE")
                        case (.bySource, .descending):
                            #sql("\($0.source) COLLATE NOCASE DESC")
                        case (.byDateModified, .ascending):
                            $0.lastModifiedDate
                        case (.byDateModified, .descending):
                            $0.lastModifiedDate.desc()
                        case (.byDateCreated, .ascending):
                            $0.createdDate
                        case (.byDateCreated, .descending):
                            $0.createdDate.desc()
                        case (.byRating, .ascending):
                            $0.rating
                        case (.byRating, .descending):
                            $0.rating.desc()
                        case (.byDifficulty, .ascending):
                            $0.difficulty
                        case (.byDifficulty, .descending):
                            $0.difficulty.desc()
                        }
                    }
            )
        } else if includeFavorites {
            // Query with favorites only
            try await $recipes.load(
                Recipe
                    .where {
                        $0.isFavorite == true
                    }
                    .order {
                        switch (sortOrder, sortDirection) {
                        case (.byName, .ascending):
                            #sql("\($0.name) COLLATE NOCASE")
                        case (.byName, .descending):
                            #sql("\($0.name) COLLATE NOCASE DESC")
                        case (.bySource, .ascending):
                            #sql("\($0.source) COLLATE NOCASE")
                        case (.bySource, .descending):
                            #sql("\($0.source) COLLATE NOCASE DESC")
                        case (.byDateModified, .ascending):
                            $0.lastModifiedDate
                        case (.byDateModified, .descending):
                            $0.lastModifiedDate.desc()
                        case (.byDateCreated, .ascending):
                            $0.createdDate
                        case (.byDateCreated, .descending):
                            $0.createdDate.desc()
                        case (.byRating, .ascending):
                            $0.rating
                        case (.byRating, .descending):
                            $0.rating.desc()
                        case (.byDifficulty, .ascending):
                            $0.difficulty
                        case (.byDifficulty, .descending):
                            $0.difficulty.desc()
                        }
                    }
            )
        } else {
            // Query without WHERE clause
            try await $recipes.load(
                Recipe.order {
                    switch (sortOrder, sortDirection) {
                    case (.byName, .ascending):
                        #sql("\($0.name) COLLATE NOCASE")
                    case (.byName, .descending):
                        #sql("\($0.name) COLLATE NOCASE DESC")
                    case (.bySource, .ascending):
                        #sql("\($0.source) COLLATE NOCASE")
                    case (.bySource, .descending):
                        #sql("\($0.source) COLLATE NOCASE DESC")
                    case (.byDateModified, .ascending):
                        $0.lastModifiedDate
                    case (.byDateModified, .descending):
                        $0.lastModifiedDate.desc()
                    case (.byDateCreated, .ascending):
                        $0.createdDate
                    case (.byDateCreated, .descending):
                        $0.createdDate.desc()
                    case (.byRating, .ascending):
                        $0.rating
                    case (.byRating, .descending):
                        $0.rating.desc()
                    case (.byDifficulty, .ascending):
                        $0.difficulty
                    case (.byDifficulty, .descending):
                        $0.difficulty.desc()
                    }
                }
            )
        }
    }
    
    private func loadCategoryRecipesQuery(categoryId: String, searchPattern: String?, includeFavorites: Bool, sortOrder: RecipeListSortOrderSetting, sortDirection: RecipeListSortDirection) async throws {
        switch (searchPattern != nil, includeFavorites, sortOrder, sortDirection) {
        case (true, true, .byName, .ascending):
            let searchPattern = searchPattern!
                    try await $recipes.load(
                        #sql(
                        """
                        SELECT DISTINCT \(Recipe.columns) FROM \(Recipe.self)
                        INNER JOIN \(RecipeCategory.self) ON \(Recipe.id) = \(RecipeCategory.recipeId)
                        WHERE \(RecipeCategory.categoryId) = \(bind: categoryId)
                        AND \(Recipe.name) COLLATE NOCASE LIKE \(bind: searchPattern)
                        AND \(Recipe.isFavorite) = \(bind: true)
                        ORDER BY \(Recipe.name) COLLATE NOCASE ASC
                        """,
                        as: Recipe.self)
                    )
        case (true, true, .byName, .descending):
            let searchPattern = searchPattern!
                    try await $recipes.load(
                        #sql(
                        """
                        SELECT DISTINCT \(Recipe.columns) FROM \(Recipe.self)
                        INNER JOIN \(RecipeCategory.self) ON \(Recipe.id) = \(RecipeCategory.recipeId)
                        WHERE \(RecipeCategory.categoryId) = \(bind: categoryId)
                        AND \(Recipe.name) COLLATE NOCASE LIKE \(bind: searchPattern)
                AND \(Recipe.isFavorite) = \(bind: true)
                ORDER BY \(Recipe.name) COLLATE NOCASE DESC
                """,
                as: Recipe.self)
            )
        case (true, true, .byDateModified, .ascending):
            let searchPattern = searchPattern!
            try await $recipes.load(
                #sql(
                """
                SELECT DISTINCT \(Recipe.columns) FROM \(Recipe.self)
                INNER JOIN \(RecipeCategory.self) ON \(Recipe.id) = \(RecipeCategory.recipeId)
                WHERE \(RecipeCategory.categoryId) = \(bind: categoryId)
                AND \(Recipe.name) COLLATE NOCASE LIKE \(bind: searchPattern)
                AND \(Recipe.isFavorite) = \(bind: true)
                ORDER BY \(Recipe.lastModifiedDate) ASC
                """,
                as: Recipe.self)
            )
        case (true, true, .byDateModified, .descending):
            let searchPattern = searchPattern!
            try await $recipes.load(
                #sql(
                """
                SELECT DISTINCT \(Recipe.columns) FROM \(Recipe.self)
                INNER JOIN \(RecipeCategory.self) ON \(Recipe.id) = \(RecipeCategory.recipeId)
                WHERE \(RecipeCategory.categoryId) = \(bind: categoryId)
                AND \(Recipe.name) COLLATE NOCASE LIKE \(bind: searchPattern)
                AND \(Recipe.isFavorite) = \(bind: true)
                ORDER BY \(Recipe.lastModifiedDate) DESC
                """,
                as: Recipe.self)
            )
        case (true, true, .byDateCreated, .ascending):
            let searchPattern = searchPattern!
            try await $recipes.load(
                #sql(
                """
                SELECT DISTINCT \(Recipe.columns) FROM \(Recipe.self)
                INNER JOIN \(RecipeCategory.self) ON \(Recipe.id) = \(RecipeCategory.recipeId)
                WHERE \(RecipeCategory.categoryId) = \(bind: categoryId)
                AND \(Recipe.name) COLLATE NOCASE LIKE \(bind: searchPattern)
                AND \(Recipe.isFavorite) = \(bind: true)
                ORDER BY \(Recipe.createdDate) ASC
                """,
                as: Recipe.self)
            )
        case (true, true, .byDateCreated, .descending):
            let searchPattern = searchPattern!
            try await $recipes.load(
                #sql(
                """
                SELECT DISTINCT \(Recipe.columns) FROM \(Recipe.self)
                INNER JOIN \(RecipeCategory.self) ON \(Recipe.id) = \(RecipeCategory.recipeId)
                WHERE \(RecipeCategory.categoryId) = \(bind: categoryId)
                AND \(Recipe.name) COLLATE NOCASE LIKE \(bind: searchPattern)
                AND \(Recipe.isFavorite) = \(bind: true)
                ORDER BY \(Recipe.createdDate) DESC
                """,
                as: Recipe.self)
            )
        case (true, true, .bySource, .ascending):
            let searchPattern = searchPattern!
            try await $recipes.load(
                #sql(
                """
                SELECT DISTINCT \(Recipe.columns) FROM \(Recipe.self)
                INNER JOIN \(RecipeCategory.self) ON \(Recipe.id) = \(RecipeCategory.recipeId)
                WHERE \(RecipeCategory.categoryId) = \(bind: categoryId)
                AND \(Recipe.name) COLLATE NOCASE LIKE \(bind: searchPattern)
                AND \(Recipe.isFavorite) = \(bind: true)
                ORDER BY \(Recipe.source) COLLATE NOCASE ASC
                """,
                as: Recipe.self)
            )
        case (true, true, .bySource, .descending):
            let searchPattern = searchPattern!
            try await $recipes.load(
                #sql(
                """
                SELECT DISTINCT \(Recipe.columns) FROM \(Recipe.self)
                INNER JOIN \(RecipeCategory.self) ON \(Recipe.id) = \(RecipeCategory.recipeId)
                WHERE \(RecipeCategory.categoryId) = \(bind: categoryId)
                AND \(Recipe.name) COLLATE NOCASE LIKE \(bind: searchPattern)
                AND \(Recipe.isFavorite) = \(bind: true)
                ORDER BY \(Recipe.source) COLLATE NOCASE DESC
                """,
                as: Recipe.self)
            )
        case (true, true, .byRating, .ascending):
            let searchPattern = searchPattern!
            try await $recipes.load(
                #sql(
                """
                SELECT DISTINCT \(Recipe.columns) FROM \(Recipe.self)
                INNER JOIN \(RecipeCategory.self) ON \(Recipe.id) = \(RecipeCategory.recipeId)
                WHERE \(RecipeCategory.categoryId) = \(bind: categoryId)
                AND \(Recipe.name) COLLATE NOCASE LIKE \(bind: searchPattern)
                AND \(Recipe.isFavorite) = \(bind: true)
                ORDER BY \(Recipe.rating) ASC
                """,
                as: Recipe.self)
            )
        case (true, true, .byRating, .descending):
            let searchPattern = searchPattern!
            try await $recipes.load(
                #sql(
                """
                SELECT DISTINCT \(Recipe.columns) FROM \(Recipe.self)
                INNER JOIN \(RecipeCategory.self) ON \(Recipe.id) = \(RecipeCategory.recipeId)
                WHERE \(RecipeCategory.categoryId) = \(bind: categoryId)
                AND \(Recipe.name) COLLATE NOCASE LIKE \(bind: searchPattern)
                AND \(Recipe.isFavorite) = \(bind: true)
                ORDER BY \(Recipe.rating) DESC
                """,
                as: Recipe.self)
            )
        case (true, true, .byDifficulty, .ascending):
            let searchPattern = searchPattern!
            try await $recipes.load(
                #sql(
                """
                SELECT DISTINCT \(Recipe.columns) FROM \(Recipe.self)
                INNER JOIN \(RecipeCategory.self) ON \(Recipe.id) = \(RecipeCategory.recipeId)
                WHERE \(RecipeCategory.categoryId) = \(bind: categoryId)
                AND \(Recipe.name) COLLATE NOCASE LIKE \(bind: searchPattern)
                AND \(Recipe.isFavorite) = \(bind: true)
                ORDER BY \(Recipe.difficulty) ASC
                """,
                as: Recipe.self)
            )
        case (true, true, .byDifficulty, .descending):
            let searchPattern = searchPattern!
            try await $recipes.load(
                #sql(
                """
                SELECT DISTINCT \(Recipe.columns) FROM \(Recipe.self)
                INNER JOIN \(RecipeCategory.self) ON \(Recipe.id) = \(RecipeCategory.recipeId)
                WHERE \(RecipeCategory.categoryId) = \(bind: categoryId)
                AND \(Recipe.name) COLLATE NOCASE LIKE \(bind: searchPattern)
                AND \(Recipe.isFavorite) = \(bind: true)
                ORDER BY \(Recipe.difficulty) DESC
                """,
                as: Recipe.self)
            )
        case (true, false, .byName, .ascending):
            let searchPattern = searchPattern!
            try await $recipes.load(
                #sql(
                """
                SELECT DISTINCT \(Recipe.columns) FROM \(Recipe.self)
                INNER JOIN \(RecipeCategory.self) ON \(Recipe.id) = \(RecipeCategory.recipeId)
                WHERE \(RecipeCategory.categoryId) = \(bind: categoryId)
                AND \(Recipe.name) COLLATE NOCASE LIKE \(bind: searchPattern)
                ORDER BY \(Recipe.name) COLLATE NOCASE ASC
                """,
                as: Recipe.self)
            )
        case (true, false, .byName, .descending):
            let searchPattern = searchPattern!
            try await $recipes.load(
                #sql(
                """
                SELECT DISTINCT \(Recipe.columns) FROM \(Recipe.self)
                INNER JOIN \(RecipeCategory.self) ON \(Recipe.id) = \(RecipeCategory.recipeId)
                WHERE \(RecipeCategory.categoryId) = \(bind: categoryId)
                AND \(Recipe.name) COLLATE NOCASE LIKE \(bind: searchPattern)
                ORDER BY \(Recipe.name) COLLATE NOCASE DESC
                """,
                as: Recipe.self)
            )
        case (true, false, .byDateModified, .ascending):
            let searchPattern = searchPattern!
            try await $recipes.load(
                #sql(
                """
                SELECT DISTINCT \(Recipe.columns) FROM \(Recipe.self)
                INNER JOIN \(RecipeCategory.self) ON \(Recipe.id) = \(RecipeCategory.recipeId)
                WHERE \(RecipeCategory.categoryId) = \(bind: categoryId)
                AND \(Recipe.name) COLLATE NOCASE LIKE \(bind: searchPattern)
                ORDER BY \(Recipe.lastModifiedDate) ASC
                """,
                as: Recipe.self)
            )
        case (true, false, .byDateModified, .descending):
            let searchPattern = searchPattern!
            try await $recipes.load(
                #sql(
                """
                SELECT DISTINCT \(Recipe.columns) FROM \(Recipe.self)
                INNER JOIN \(RecipeCategory.self) ON \(Recipe.id) = \(RecipeCategory.recipeId)
                WHERE \(RecipeCategory.categoryId) = \(bind: categoryId)
                AND \(Recipe.name) COLLATE NOCASE LIKE \(bind: searchPattern)
                ORDER BY \(Recipe.lastModifiedDate) DESC
                """,
                as: Recipe.self)
            )
        case (true, false, .byDateCreated, .ascending):
            let searchPattern = searchPattern!
            try await $recipes.load(
                #sql(
                """
                SELECT DISTINCT \(Recipe.columns) FROM \(Recipe.self)
                INNER JOIN \(RecipeCategory.self) ON \(Recipe.id) = \(RecipeCategory.recipeId)
                WHERE \(RecipeCategory.categoryId) = \(bind: categoryId)
                AND \(Recipe.name) COLLATE NOCASE LIKE \(bind: searchPattern)
                ORDER BY \(Recipe.createdDate) ASC
                """,
                as: Recipe.self)
            )
        case (true, false, .byDateCreated, .descending):
            let searchPattern = searchPattern!
            try await $recipes.load(
                #sql(
                """
                SELECT DISTINCT \(Recipe.columns) FROM \(Recipe.self)
                INNER JOIN \(RecipeCategory.self) ON \(Recipe.id) = \(RecipeCategory.recipeId)
                WHERE \(RecipeCategory.categoryId) = \(bind: categoryId)
                AND \(Recipe.name) COLLATE NOCASE LIKE \(bind: searchPattern)
                ORDER BY \(Recipe.createdDate) DESC
                """,
                as: Recipe.self)
            )
        case (true, false, .bySource, .ascending):
            let searchPattern = searchPattern!
            try await $recipes.load(
                #sql(
                """
                SELECT DISTINCT \(Recipe.columns) FROM \(Recipe.self)
                INNER JOIN \(RecipeCategory.self) ON \(Recipe.id) = \(RecipeCategory.recipeId)
                WHERE \(RecipeCategory.categoryId) = \(bind: categoryId)
                AND \(Recipe.name) COLLATE NOCASE LIKE \(bind: searchPattern)
                ORDER BY \(Recipe.source) COLLATE NOCASE ASC
                """,
                as: Recipe.self)
            )
        case (true, false, .bySource, .descending):
            let searchPattern = searchPattern!
            try await $recipes.load(
                #sql(
                """
                SELECT DISTINCT \(Recipe.columns) FROM \(Recipe.self)
                INNER JOIN \(RecipeCategory.self) ON \(Recipe.id) = \(RecipeCategory.recipeId)
                WHERE \(RecipeCategory.categoryId) = \(bind: categoryId)
                AND \(Recipe.name) COLLATE NOCASE LIKE \(bind: searchPattern)
                ORDER BY \(Recipe.source) COLLATE NOCASE DESC
                """,
                as: Recipe.self)
            )
        case (true, false, .byRating, .ascending):
            let searchPattern = searchPattern!
            try await $recipes.load(
                #sql(
                """
                SELECT DISTINCT \(Recipe.columns) FROM \(Recipe.self)
                INNER JOIN \(RecipeCategory.self) ON \(Recipe.id) = \(RecipeCategory.recipeId)
                WHERE \(RecipeCategory.categoryId) = \(bind: categoryId)
                AND \(Recipe.name) COLLATE NOCASE LIKE \(bind: searchPattern)
                ORDER BY \(Recipe.rating) ASC
                """,
                as: Recipe.self)
            )
        case (true, false, .byRating, .descending):
            let searchPattern = searchPattern!
            try await $recipes.load(
                #sql(
                """
                SELECT DISTINCT \(Recipe.columns) FROM \(Recipe.self)
                INNER JOIN \(RecipeCategory.self) ON \(Recipe.id) = \(RecipeCategory.recipeId)
                WHERE \(RecipeCategory.categoryId) = \(bind: categoryId)
                AND \(Recipe.name) COLLATE NOCASE LIKE \(bind: searchPattern)
                ORDER BY \(Recipe.rating) DESC
                """,
                as: Recipe.self)
            )
        case (true, false, .byDifficulty, .ascending):
            let searchPattern = searchPattern!
            try await $recipes.load(
                #sql(
                """
                SELECT DISTINCT \(Recipe.columns) FROM \(Recipe.self)
                INNER JOIN \(RecipeCategory.self) ON \(Recipe.id) = \(RecipeCategory.recipeId)
                WHERE \(RecipeCategory.categoryId) = \(bind: categoryId)
                AND \(Recipe.name) COLLATE NOCASE LIKE \(bind: searchPattern)
                ORDER BY \(Recipe.difficulty) ASC
                """,
                as: Recipe.self)
            )
        case (true, false, .byDifficulty, .descending):
            let searchPattern = searchPattern!
            try await $recipes.load(
                #sql(
                """
                SELECT DISTINCT \(Recipe.columns) FROM \(Recipe.self)
                INNER JOIN \(RecipeCategory.self) ON \(Recipe.id) = \(RecipeCategory.recipeId)
                WHERE \(RecipeCategory.categoryId) = \(bind: categoryId)
                AND \(Recipe.name) COLLATE NOCASE LIKE \(bind: searchPattern)
                ORDER BY \(Recipe.difficulty) DESC
                """,
                as: Recipe.self)
            )
        case (false, true, .byName, .ascending):
            try await $recipes.load(
                #sql(
                """
                SELECT DISTINCT \(Recipe.columns) FROM \(Recipe.self)
                INNER JOIN \(RecipeCategory.self) ON \(Recipe.id) = \(RecipeCategory.recipeId)
                WHERE \(RecipeCategory.categoryId) = \(bind: categoryId)
                AND \(Recipe.isFavorite) = \(bind: true)
                ORDER BY \(Recipe.name) COLLATE NOCASE ASC
                """,
                as: Recipe.self)
            )
        case (false, true, .byName, .descending):
            try await $recipes.load(
                #sql(
                """
                SELECT DISTINCT \(Recipe.columns) FROM \(Recipe.self)
                INNER JOIN \(RecipeCategory.self) ON \(Recipe.id) = \(RecipeCategory.recipeId)
                WHERE \(RecipeCategory.categoryId) = \(bind: categoryId)
                AND \(Recipe.isFavorite) = \(bind: true)
                ORDER BY \(Recipe.name) COLLATE NOCASE DESC
                """,
                as: Recipe.self)
            )
        case (false, true, .byDateModified, .ascending):
            try await $recipes.load(
                #sql(
                """
                SELECT DISTINCT \(Recipe.columns) FROM \(Recipe.self)
                INNER JOIN \(RecipeCategory.self) ON \(Recipe.id) = \(RecipeCategory.recipeId)
                WHERE \(RecipeCategory.categoryId) = \(bind: categoryId)
                AND \(Recipe.isFavorite) = \(bind: true)
                ORDER BY \(Recipe.lastModifiedDate) ASC
                """,
                as: Recipe.self)
            )
        case (false, true, .byDateModified, .descending):
            try await $recipes.load(
                #sql(
                """
                SELECT DISTINCT \(Recipe.columns) FROM \(Recipe.self)
                INNER JOIN \(RecipeCategory.self) ON \(Recipe.id) = \(RecipeCategory.recipeId)
                WHERE \(RecipeCategory.categoryId) = \(bind: categoryId)
                AND \(Recipe.isFavorite) = \(bind: true)
                ORDER BY \(Recipe.lastModifiedDate) DESC
                """,
                as: Recipe.self)
            )
        case (false, true, .byDateCreated, .ascending):
            try await $recipes.load(
                #sql(
                """
                SELECT DISTINCT \(Recipe.columns) FROM \(Recipe.self)
                INNER JOIN \(RecipeCategory.self) ON \(Recipe.id) = \(RecipeCategory.recipeId)
                WHERE \(RecipeCategory.categoryId) = \(bind: categoryId)
                AND \(Recipe.isFavorite) = \(bind: true)
                ORDER BY \(Recipe.createdDate) ASC
                """,
                as: Recipe.self)
            )
        case (false, true, .byDateCreated, .descending):
            try await $recipes.load(
                #sql(
                """
                SELECT DISTINCT \(Recipe.columns) FROM \(Recipe.self)
                INNER JOIN \(RecipeCategory.self) ON \(Recipe.id) = \(RecipeCategory.recipeId)
                WHERE \(RecipeCategory.categoryId) = \(bind: categoryId)
                AND \(Recipe.isFavorite) = \(bind: true)
                ORDER BY \(Recipe.createdDate) DESC
                """,
                as: Recipe.self)
            )
        case (false, true, .bySource, .ascending):
            try await $recipes.load(
                #sql(
                """
                SELECT DISTINCT \(Recipe.columns) FROM \(Recipe.self)
                INNER JOIN \(RecipeCategory.self) ON \(Recipe.id) = \(RecipeCategory.recipeId)
                WHERE \(RecipeCategory.categoryId) = \(bind: categoryId)
                AND \(Recipe.isFavorite) = \(bind: true)
                ORDER BY \(Recipe.source) COLLATE NOCASE ASC
                """,
                as: Recipe.self)
            )
        case (false, true, .bySource, .descending):
            try await $recipes.load(
                #sql(
                """
                SELECT DISTINCT \(Recipe.columns) FROM \(Recipe.self)
                INNER JOIN \(RecipeCategory.self) ON \(Recipe.id) = \(RecipeCategory.recipeId)
                WHERE \(RecipeCategory.categoryId) = \(bind: categoryId)
                AND \(Recipe.isFavorite) = \(bind: true)
                ORDER BY \(Recipe.source) COLLATE NOCASE DESC
                """,
                as: Recipe.self)
            )
        case (false, true, .byRating, .ascending):
            try await $recipes.load(
                #sql(
                """
                SELECT DISTINCT \(Recipe.columns) FROM \(Recipe.self)
                INNER JOIN \(RecipeCategory.self) ON \(Recipe.id) = \(RecipeCategory.recipeId)
                WHERE \(RecipeCategory.categoryId) = \(bind: categoryId)
                AND \(Recipe.isFavorite) = \(bind: true)
                ORDER BY \(Recipe.rating) ASC
                """,
                as: Recipe.self)
            )
        case (false, true, .byRating, .descending):
            try await $recipes.load(
                #sql(
                """
                SELECT DISTINCT \(Recipe.columns) FROM \(Recipe.self)
                INNER JOIN \(RecipeCategory.self) ON \(Recipe.id) = \(RecipeCategory.recipeId)
                WHERE \(RecipeCategory.categoryId) = \(bind: categoryId)
                AND \(Recipe.isFavorite) = \(bind: true)
                ORDER BY \(Recipe.rating) DESC
                """,
                as: Recipe.self)
            )
        case (false, true, .byDifficulty, .ascending):
            try await $recipes.load(
                #sql(
                """
                SELECT DISTINCT \(Recipe.columns) FROM \(Recipe.self)
                INNER JOIN \(RecipeCategory.self) ON \(Recipe.id) = \(RecipeCategory.recipeId)
                WHERE \(RecipeCategory.categoryId) = \(bind: categoryId)
                AND \(Recipe.isFavorite) = \(bind: true)
                ORDER BY \(Recipe.difficulty) ASC
                """,
                as: Recipe.self)
            )
        case (false, true, .byDifficulty, .descending):
            try await $recipes.load(
                #sql(
                """
                SELECT DISTINCT \(Recipe.columns) FROM \(Recipe.self)
                INNER JOIN \(RecipeCategory.self) ON \(Recipe.id) = \(RecipeCategory.recipeId)
                WHERE \(RecipeCategory.categoryId) = \(bind: categoryId)
                AND \(Recipe.isFavorite) = \(bind: true)
                ORDER BY \(Recipe.difficulty) DESC
                """,
                as: Recipe.self)
            )
        case (false, false, .byName, .ascending):
            try await $recipes.load(
                #sql(
                """
                SELECT DISTINCT \(Recipe.columns) FROM \(Recipe.self)
                INNER JOIN \(RecipeCategory.self) ON \(Recipe.id) = \(RecipeCategory.recipeId)
                WHERE \(RecipeCategory.categoryId) = \(bind: categoryId)
                ORDER BY \(Recipe.name) COLLATE NOCASE ASC
                """,
                as: Recipe.self)
            )
        case (false, false, .byName, .descending):
            try await $recipes.load(
                #sql(
                """
                SELECT DISTINCT \(Recipe.columns) FROM \(Recipe.self)
                INNER JOIN \(RecipeCategory.self) ON \(Recipe.id) = \(RecipeCategory.recipeId)
                WHERE \(RecipeCategory.categoryId) = \(bind: categoryId)
                ORDER BY \(Recipe.name) COLLATE NOCASE DESC
                """,
                as: Recipe.self)
            )
        case (false, false, .byDateModified, .ascending):
            try await $recipes.load(
                #sql(
                """
                SELECT DISTINCT \(Recipe.columns) FROM \(Recipe.self)
                INNER JOIN \(RecipeCategory.self) ON \(Recipe.id) = \(RecipeCategory.recipeId)
                WHERE \(RecipeCategory.categoryId) = \(bind: categoryId)
                ORDER BY \(Recipe.lastModifiedDate) ASC
                """,
                as: Recipe.self)
            )
        case (false, false, .byDateModified, .descending):
            try await $recipes.load(
                #sql(
                """
                SELECT DISTINCT \(Recipe.columns) FROM \(Recipe.self)
                INNER JOIN \(RecipeCategory.self) ON \(Recipe.id) = \(RecipeCategory.recipeId)
                WHERE \(RecipeCategory.categoryId) = \(bind: categoryId)
                ORDER BY \(Recipe.lastModifiedDate) DESC
                """,
                as: Recipe.self)
            )
        case (false, false, .byDateCreated, .ascending):
            try await $recipes.load(
                #sql(
                """
                SELECT DISTINCT \(Recipe.columns) FROM \(Recipe.self)
                INNER JOIN \(RecipeCategory.self) ON \(Recipe.id) = \(RecipeCategory.recipeId)
                WHERE \(RecipeCategory.categoryId) = \(bind: categoryId)
                ORDER BY \(Recipe.createdDate) ASC
                """,
                as: Recipe.self)
            )
        case (false, false, .byDateCreated, .descending):
            try await $recipes.load(
                #sql(
                """
                SELECT DISTINCT \(Recipe.columns) FROM \(Recipe.self)
                INNER JOIN \(RecipeCategory.self) ON \(Recipe.id) = \(RecipeCategory.recipeId)
                WHERE \(RecipeCategory.categoryId) = \(bind: categoryId)
                ORDER BY \(Recipe.createdDate) DESC
                """,
                as: Recipe.self)
            )
        case (false, false, .bySource, .ascending):
            try await $recipes.load(
                #sql(
                """
                SELECT DISTINCT \(Recipe.columns) FROM \(Recipe.self)
                INNER JOIN \(RecipeCategory.self) ON \(Recipe.id) = \(RecipeCategory.recipeId)
                WHERE \(RecipeCategory.categoryId) = \(bind: categoryId)
                ORDER BY \(Recipe.source) COLLATE NOCASE ASC
                """,
                as: Recipe.self)
            )
        case (false, false, .bySource, .descending):
            try await $recipes.load(
                #sql(
                """
                SELECT DISTINCT \(Recipe.columns) FROM \(Recipe.self)
                INNER JOIN \(RecipeCategory.self) ON \(Recipe.id) = \(RecipeCategory.recipeId)
                WHERE \(RecipeCategory.categoryId) = \(bind: categoryId)
                ORDER BY \(Recipe.source) COLLATE NOCASE DESC
                """,
                as: Recipe.self)
            )
        case (false, false, .byRating, .ascending):
            try await $recipes.load(
                #sql(
                """
                SELECT DISTINCT \(Recipe.columns) FROM \(Recipe.self)
                INNER JOIN \(RecipeCategory.self) ON \(Recipe.id) = \(RecipeCategory.recipeId)
                WHERE \(RecipeCategory.categoryId) = \(bind: categoryId)
                ORDER BY \(Recipe.rating) ASC
                """,
                as: Recipe.self)
            )
        case (false, false, .byRating, .descending):
            try await $recipes.load(
                #sql(
                """
                SELECT DISTINCT \(Recipe.columns) FROM \(Recipe.self)
                INNER JOIN \(RecipeCategory.self) ON \(Recipe.id) = \(RecipeCategory.recipeId)
                WHERE \(RecipeCategory.categoryId) = \(bind: categoryId)
                ORDER BY \(Recipe.rating) DESC
                """,
                as: Recipe.self)
            )
        case (false, false, .byDifficulty, .ascending):
            try await $recipes.load(
                #sql(
                """
                SELECT DISTINCT \(Recipe.columns) FROM \(Recipe.self)
                INNER JOIN \(RecipeCategory.self) ON \(Recipe.id) = \(RecipeCategory.recipeId)
                WHERE \(RecipeCategory.categoryId) = \(bind: categoryId)
                ORDER BY \(Recipe.difficulty) ASC
                """,
                as: Recipe.self)
            )
        case (false, false, .byDifficulty, .descending):
            try await $recipes.load(
                #sql(
                """
                SELECT DISTINCT \(Recipe.columns) FROM \(Recipe.self)
                INNER JOIN \(RecipeCategory.self) ON \(Recipe.id) = \(RecipeCategory.recipeId)
                WHERE \(RecipeCategory.categoryId) = \(bind: categoryId)
                ORDER BY \(Recipe.difficulty) DESC
                """,
                as: Recipe.self)
            )
        }
    }
    
    func updateRecipesQuery() async {
        do {
            let isAllRecipes = selectedSidebarItemId == nil || selectedSidebarItemId == allRecipesID
            let searchPattern = searchString.isEmpty ? nil : "%\(searchString)%"
            let includeFavorites = isFavoritesFilterActive
            
            if isAllRecipes {
                try await loadAllRecipesQuery(searchPattern: searchPattern, includeFavorites: includeFavorites, sortOrder: recipeListSortOrder, sortDirection: recipeListSortDirection)
            } else if let categoryId = selectedSidebarItemId {
                try await loadCategoryRecipesQuery(categoryId: categoryId, searchPattern: searchPattern, includeFavorites: includeFavorites, sortOrder: recipeListSortOrder, sortDirection: recipeListSortDirection)
            }
        }
        catch {
            print("Error fetching recipes: \(error)")
            logger.error("Error fetching recipes: \(error)")
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
    }
    
    func deleteSelectedRecipes() {
        do {
            // First, get the image filenames from selected recipes before deleting them
            let imageFilenames = try database.read { db in
                try Recipe
                    .select { $0.imageFilename }
                    .where { selectedRecipeIDs.contains($0.id) }
                    .fetchAll(db)
            }
             
            // Delete image files from filesystem
            for imageFilename in imageFilenames {
                if let filename = imageFilename {
                    RecipeImageManager.shared.deleteImage(filename: filename)
                }
            }
            
            // Now delete the recipes from the database
            let _ = try database.write { db in
                try Recipe
                    .where { selectedRecipeIDs.contains($0.id) }
                    .delete()
                    .execute(db)
            }
            
            selectedRecipeIDs.removeAll()
        } catch {
            logger.error("Error deleting recipes: \(error)")
        }
    }
    
    func deleteRecipe(id: String) {
        do {
            // First, get the image filename from the recipe before deleting it
            let imageFilenames = try database.read { db in
                try Recipe
                    .select { $0.imageFilename }
                    .where { $0.id == id }
                    .fetchAll(db)
            }
            
            // Delete image file from filesystem if it exists
            for imageFilename in imageFilenames {
                if let filename = imageFilename {
                    RecipeImageManager.shared.deleteImage(filename: filename)
                }
            }
            
            // Now delete the recipe from the database
            let _ = try database.write { db in
                try Recipe
                    .where { $0.id == id }
                    .delete()
                    .execute(db)
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
    
    /// Creates a shareable recipe export for the given recipe
    /// - Parameter recipe: The recipe to convert to a shareable format
    /// - Returns: A SaltyRecipeExport if successful, nil otherwise
    func shareableRecipe(for recipe: Recipe) -> SaltyRecipeExport? {
        do {
            let shareableRecipe = try SaltyRecipeExport.fromRecipe(recipe, database: database)
            return shareableRecipe
        }
        catch {
            return nil
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
    
    /// Imports sample recipes from the app Resources directory
    func importSampleRecipes() async {
        let x =  Bundle.main.url(forResource: "DemoRecipes", withExtension: "saltyRecipe")
        let y = Bundle.main.bundlePath
        let s = x?.description ?? "no url"
        logger.info("path = \(y)")
        logger.info("\(s)")
        if let demoImportUrl = Bundle.main.url(forResource: "DemoRecipes", withExtension: "saltyRecipe") {
            do {
                try await SaltyRecipeImportHelper.importIntoDatabase(database, jsonFileUrl: demoImportUrl)
                logger.info("Successfully imported sample recipes")
            } catch {
                logger.error("Failed to import sample recipes: \(error.localizedDescription)")
            }
        }
        else {
            logger.info("Failed to locate sample recipe data")
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
