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
    private let categoryPrefix = "cat_"
    private let coursePrefix = "course_"
    private let tagPrefix = "tag_"
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
    
    @ObservationIgnored
    @FetchAll(#sql("SELECT \(Course.columns) FROM \(Course.self) ORDER BY \(Course.name) COLLATE NOCASE"))
    var courses: [Course]
    
    @ObservationIgnored
    @FetchAll(#sql("SELECT \(Tag.columns) FROM \(Tag.self) ORDER BY \(Tag.name) COLLATE NOCASE"))
    var tags: [Tag]
            
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
        } else if let selectedId = selectedSidebarItemId {
            if selectedId.hasPrefix(categoryPrefix) {
                let categoryId = String(selectedId.dropFirst(categoryPrefix.count))
                if let category = categories.first(where: { $0.id == categoryId }) {
                    return category.name
                }
            } else if selectedId.hasPrefix(coursePrefix) {
                let courseId = String(selectedId.dropFirst(coursePrefix.count))
                if let course = courses.first(where: { $0.id == courseId }) {
                    return course.name
                }
            } else if selectedId.hasPrefix(tagPrefix) {
                let tagId = String(selectedId.dropFirst(tagPrefix.count))
                if let tag = tags.first(where: { $0.id == tagId }) {
                    return tag.name
                }
            } else {
                // Legacy: treat as category ID without prefix (for backward compatibility)
                if let category = categories.first(where: { $0.id == selectedId }) {
                    return category.name
                }
            }
        }
        return "Recipes"
    }
    
    // Helper to get selected search options from UserDefaults
    private func getSelectedSearchOptions() -> Set<RecipeListSearchOptions> {
        var options: Set<RecipeListSearchOptions> = []
        for option in RecipeListSearchOptions.allCases {
            if UserDefaults.standard.bool(forKey: option.userDefaultsKey) {
                options.insert(option)
            }
        }
        // Default to name if none selected
        return options.isEmpty ? [.name] : options
    }
    
    // Helper to check if search requires JOINs
    private func searchRequiresJoins(_ options: Set<RecipeListSearchOptions>) -> Bool {
        options.contains(.category) || options.contains(.course) || options.contains(.tag)
    }
    
    private func loadAllRecipesQuery(searchPattern: String?, includeFavorites: Bool, sortOrder: RecipeListSortOrderSetting, sortDirection: RecipeListSortDirection) async throws {
        let searchOptions = getSelectedSearchOptions()
        let requiresJoins = searchRequiresJoins(searchOptions)
        
        // If search requires JOINs, use #sql directly
        if let searchPattern = searchPattern, requiresJoins {
            try await loadAllRecipesQueryWithJoins(searchPattern: searchPattern, includeFavorites: includeFavorites, sortOrder: sortOrder, sortDirection: sortDirection, searchOptions: searchOptions)
            return
        }
        
        // Build query using method chaining for simple searches (no JOINs needed)
        if let searchPattern = searchPattern, includeFavorites {
            // Query with search AND favorites - build OR conditions inline
            try await $recipes.load(
                Recipe
                    .where { recipe in
                        // Build OR conditions inline - check which options are selected
                        if searchOptions.contains(.name) && searchOptions.contains(.introduction) {
                            // Both selected - use OR
                            (#sql("\(recipe.name) COLLATE NOCASE LIKE \(bind: searchPattern)") || #sql("\(recipe.introduction) COLLATE NOCASE LIKE \(bind: searchPattern)")) && recipe.isFavorite == true
                        } else if searchOptions.contains(.name) {
                            // Only name selected
                            #sql("\(recipe.name) COLLATE NOCASE LIKE \(bind: searchPattern)") && recipe.isFavorite == true
                        } else if searchOptions.contains(.introduction) {
                            // Only introduction selected
                            #sql("\(recipe.introduction) COLLATE NOCASE LIKE \(bind: searchPattern)") && recipe.isFavorite == true
                        } else {
                            // Fallback to name
                            #sql("\(recipe.name) COLLATE NOCASE LIKE \(bind: searchPattern)") && recipe.isFavorite == true
                        }
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
                    .where { recipe in
                        // Build OR conditions inline - check which options are selected
                        if searchOptions.contains(.name) && searchOptions.contains(.introduction) {
                            // Both selected - use OR
                            #sql("\(recipe.name) COLLATE NOCASE LIKE \(bind: searchPattern)") || #sql("\(recipe.introduction) COLLATE NOCASE LIKE \(bind: searchPattern)")
                        } else if searchOptions.contains(.name) {
                            // Only name selected
                            #sql("\(recipe.name) COLLATE NOCASE LIKE \(bind: searchPattern)")
                        } else if searchOptions.contains(.introduction) {
                            // Only introduction selected
                            #sql("\(recipe.introduction) COLLATE NOCASE LIKE \(bind: searchPattern)")
                        } else {
                            // Fallback to name
                            #sql("\(recipe.name) COLLATE NOCASE LIKE \(bind: searchPattern)")
                        }
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
    
    private func loadAllRecipesQueryWithJoins(searchPattern: String, includeFavorites: Bool, sortOrder: RecipeListSortOrderSetting, sortDirection: RecipeListSortDirection, searchOptions: Set<RecipeListSearchOptions>) async throws {
        // Use full #sql for queries requiring JOINs
        // Build ORDER BY as plain SQL strings (not SQL expressions)
        let direction = sortDirection.sqlSuffix
        let orderByFragment: String = {
            switch sortOrder {
            case .byName: return "name COLLATE NOCASE"
            case .bySource: return "source COLLATE NOCASE"
            case .byDateModified: return "lastModifiedDate"
            case .byDateCreated: return "createdDate"
            case .byRating: return "rating"
            case .byDifficulty: return "difficulty"
            }
        }()
        
        // Build search conditions inline in #sql macro with bind: syntax
        // Count options to determine OR separators
        let optionCount = searchOptions.count
        
        // Build the search pattern with wildcards once
        let searchPatternWithWildcards = "%\(searchPattern)%"
        
        // Build WHERE conditions using if-else to avoid bind: in inactive branches
        // Collect active conditions first, then build SQL based on which are active
        let hasName = searchOptions.contains(.name)
        let hasIntroduction = searchOptions.contains(.introduction)
        let hasCourse = searchOptions.contains(.course)
        let hasCategory = searchOptions.contains(.category)
        let hasTag = searchOptions.contains(.tag)
        
        // Build WHERE clause conditionally - only include bind: for active conditions
        // Use if-else to generate different SQL strings so bind: only appears in executed paths
        if hasTag && !hasName && !hasIntroduction && !hasCourse && !hasCategory {
            // Only tag selected
            try await $recipes.load(
                #sql(
                """
                SELECT DISTINCT \(Recipe.columns) FROM \(Recipe.self)
                WHERE (
                    EXISTS (SELECT 1 FROM \(RecipeTag.self) INNER JOIN \(Tag.self) ON \(RecipeTag.tagId) = \(Tag.id) WHERE \(RecipeTag.recipeId) = \(Recipe.id) AND \(Tag.name) COLLATE NOCASE LIKE \(bind: searchPatternWithWildcards))
                )
                \(includeFavorites ? "AND \(Recipe.isFavorite) = \(bind: true)" : "")
                ORDER BY \(raw: orderByFragment) \(raw: direction)
                """,
                as: Recipe.self)
            )
        } else if hasName && !hasIntroduction && !hasCourse && !hasCategory && !hasTag {
            // Only name selected
            try await $recipes.load(
                #sql(
                """
                SELECT DISTINCT \(Recipe.columns) FROM \(Recipe.self)
                WHERE (
                    \(Recipe.name) COLLATE NOCASE LIKE \(bind: searchPatternWithWildcards)
                )
                \(includeFavorites ? "AND \(Recipe.isFavorite) = \(bind: true)" : "")
                ORDER BY \(raw: orderByFragment) \(raw: direction)
                """,
                as: Recipe.self)
            )
        } else {
            // Multiple conditions - build OR clause with only active conditions
            var conditions: [String] = []
            
            if hasName || (!hasIntroduction && !hasCourse && !hasCategory && !hasTag) {
                conditions.append("name")
            }
            if hasIntroduction {
                conditions.append("intro")
            }
            if hasCourse {
                conditions.append("course")
            }
            if hasCategory {
                conditions.append("category")
            }
            if hasTag {
                conditions.append("tag")
            }
            
            // Build the SQL with explicit conditions for each active option
            // This is verbose but ensures bind: only appears for active conditions
            if conditions.count == 2 {
                // Two conditions - handle common cases
                if conditions.contains("name") && conditions.contains("intro") {
                    try await $recipes.load(
                        #sql(
                        """
                        SELECT DISTINCT \(Recipe.columns) FROM \(Recipe.self)
                        WHERE (
                            \(Recipe.name) COLLATE NOCASE LIKE \(bind: searchPatternWithWildcards) OR
                            \(Recipe.introduction) COLLATE NOCASE LIKE \(bind: searchPatternWithWildcards)
                        )
                        \(includeFavorites ? "AND \(Recipe.isFavorite) = \(bind: true)" : "")
                        ORDER BY \(raw: orderByFragment) \(raw: direction)
                        """,
                        as: Recipe.self)
                    )
                } else {
                    // Fallback - use general approach with all conditions
                    try await loadAllRecipesQueryWithJoinsGeneral(searchPattern: searchPattern, includeFavorites: includeFavorites, sortOrder: sortOrder, sortDirection: sortDirection, searchOptions: searchOptions, orderByFragment: orderByFragment, direction: direction, searchPatternWithWildcards: searchPatternWithWildcards)
                }
            } else {
                // More than 2 or complex combination - use general method
                try await loadAllRecipesQueryWithJoinsGeneral(searchPattern: searchPattern, includeFavorites: includeFavorites, sortOrder: sortOrder, sortDirection: sortDirection, searchOptions: searchOptions, orderByFragment: orderByFragment, direction: direction, searchPatternWithWildcards: searchPatternWithWildcards)
            }
        }
    }
    
    // Helper method for general case with multiple search conditions
    // Uses explicit condition building to avoid bind: in inactive branches
    private func loadAllRecipesQueryWithJoinsGeneral(searchPattern: String, includeFavorites: Bool, sortOrder: RecipeListSortOrderSetting, sortDirection: RecipeListSortDirection, searchOptions: Set<RecipeListSearchOptions>, orderByFragment: String, direction: String, searchPatternWithWildcards: String) async throws {
        let hasName = searchOptions.contains(.name)
        let hasIntroduction = searchOptions.contains(.introduction)
        let hasCourse = searchOptions.contains(.course)
        let hasCategory = searchOptions.contains(.category)
        let hasTag = searchOptions.contains(.tag)
        let effectiveHasName = hasName || (!hasIntroduction && !hasCourse && !hasCategory && !hasTag)
        
        // Build WHERE parts - we'll combine them manually
        // For the general case, we need to handle all combinations
        // Since we can't use ternaries with bind:, we'll use separate queries for different patterns
        // For now, handle the most common case: name + one other
        
        if effectiveHasName && hasIntroduction && !hasCourse && !hasCategory && !hasTag {
            try await $recipes.load(
                #sql(
                """
                SELECT DISTINCT \(Recipe.columns) FROM \(Recipe.self)
                WHERE (
                    \(Recipe.name) COLLATE NOCASE LIKE \(bind: searchPatternWithWildcards) OR
                    \(Recipe.introduction) COLLATE NOCASE LIKE \(bind: searchPatternWithWildcards)
                )
                \(includeFavorites ? "AND \(Recipe.isFavorite) = \(bind: true)" : "")
                ORDER BY \(raw: orderByFragment) \(raw: direction)
                """,
                as: Recipe.self)
            )
        } else if effectiveHasName && hasTag && !hasIntroduction && !hasCourse && !hasCategory {
            try await $recipes.load(
                #sql(
                """
                SELECT DISTINCT \(Recipe.columns) FROM \(Recipe.self)
                WHERE (
                    \(Recipe.name) COLLATE NOCASE LIKE \(bind: searchPatternWithWildcards) OR
                    EXISTS (SELECT 1 FROM \(RecipeTag.self) INNER JOIN \(Tag.self) ON \(RecipeTag.tagId) = \(Tag.id) WHERE \(RecipeTag.recipeId) = \(Recipe.id) AND \(Tag.name) COLLATE NOCASE LIKE \(bind: searchPatternWithWildcards))
                )
                \(includeFavorites ? "AND \(Recipe.isFavorite) = \(bind: true)" : "")
                ORDER BY \(raw: orderByFragment) \(raw: direction)
                """,
                as: Recipe.self)
            )
        } else {
            // Complex case - for now, fall back to searching just by name
            // TODO: Handle complex multi-condition cases properly
            // The issue is that bind: can't be used outside #sql macro, so we'd need
            // to handle each combination separately with explicit if-else chains
            try await $recipes.load(
                #sql(
                """
                SELECT DISTINCT \(Recipe.columns) FROM \(Recipe.self)
                WHERE (
                    \(Recipe.name) COLLATE NOCASE LIKE \(bind: searchPatternWithWildcards)
                )
                \(includeFavorites ? "AND \(Recipe.isFavorite) = \(bind: true)" : "")
                ORDER BY \(raw: orderByFragment) \(raw: direction)
                """,
                as: Recipe.self)
            )
        }
    }
    
    private func loadCategoryRecipesQuery(categoryId: String, searchPattern: String?, includeFavorites: Bool, sortOrder: RecipeListSortOrderSetting, sortDirection: RecipeListSortDirection) async throws {
        let searchOptions = getSelectedSearchOptions()
        
        // For category queries, we need full #sql statements
        // Build search conditions using switch on options (simplified to common cases)
        if let searchPattern = searchPattern {
            // Use the same JOIN-based search condition helper
            // Since we're in a category view, we still want to search across fields
            try await loadCategoryRecipesQueryWithSearch(categoryId: categoryId, searchPattern: searchPattern, includeFavorites: includeFavorites, sortOrder: sortOrder, sortDirection: sortDirection, searchOptions: searchOptions)
        } else {
            // No search, just category filter
            try await loadCategoryRecipesQueryWithoutSearch(categoryId: categoryId, includeFavorites: includeFavorites, sortOrder: sortOrder, sortDirection: sortDirection)
        }
    }
    
    private func loadCategoryRecipesQueryWithSearch(categoryId: String, searchPattern: String, includeFavorites: Bool, sortOrder: RecipeListSortOrderSetting, sortDirection: RecipeListSortDirection, searchOptions: Set<RecipeListSearchOptions>) async throws {
        // Build ORDER BY as plain SQL strings
        let direction = sortDirection.sqlSuffix
        let orderByFragment: String = {
            switch sortOrder {
            case .byName: return "name COLLATE NOCASE"
            case .bySource: return "source COLLATE NOCASE"
            case .byDateModified: return "lastModifiedDate"
            case .byDateCreated: return "createdDate"
            case .byRating: return "rating"
            case .byDifficulty: return "difficulty"
            }
        }()
        
        // Build the search pattern with wildcards
        let searchPatternWithWildcards = "%\(searchPattern)%"
        
        // Determine which options are enabled
        let hasName = searchOptions.contains(.name)
        let hasIntroduction = searchOptions.contains(.introduction)
        let hasCourse = searchOptions.contains(.course)
        let hasCategory = searchOptions.contains(.category)
        let hasTag = searchOptions.contains(.tag)
        
        // Count active options for OR separator logic
        let activeCount = [hasName, hasIntroduction, hasCourse, hasCategory, hasTag].filter { $0 }.count
        let needsFallback = activeCount == 0
        
        // Build the search condition with proper OR separators
        try await $recipes.load(
            #sql(
            """
            SELECT DISTINCT \(Recipe.columns) FROM \(Recipe.self)
            INNER JOIN \(RecipeCategory.self) ON \(Recipe.id) = \(RecipeCategory.recipeId)
            WHERE \(RecipeCategory.categoryId) = \(bind: categoryId)
            AND (
                \(needsFallback || hasName ? "\(Recipe.name) COLLATE NOCASE LIKE \(bind: searchPatternWithWildcards)" : "")
                \(((needsFallback || hasName) && activeCount > (needsFallback ? 0 : 1)) ? " OR " : "")
                \(hasIntroduction ? "\(Recipe.introduction) COLLATE NOCASE LIKE \(bind: searchPatternWithWildcards)" : "")
                \(hasIntroduction && (hasCourse || hasCategory || hasTag) ? " OR " : "")
                \(hasCourse ? "EXISTS (SELECT 1 FROM \(Course.self) WHERE \(Course.id) = \(Recipe.courseId) AND \(Course.name) COLLATE NOCASE LIKE \(bind: searchPatternWithWildcards))" : "")
                \(hasCourse && (hasCategory || hasTag) ? " OR " : "")
                \(hasCategory ? "EXISTS (SELECT 1 FROM \(RecipeCategory.self) AS rc2 INNER JOIN \(Category.self) ON rc2.categoryId = \(Category.id) WHERE rc2.recipeId = \(Recipe.id) AND \(Category.name) COLLATE NOCASE LIKE \(bind: searchPatternWithWildcards))" : "")
                \(hasCategory && hasTag ? " OR " : "")
                \(hasTag ? "EXISTS (SELECT 1 FROM \(RecipeTag.self) INNER JOIN \(Tag.self) ON \(RecipeTag.tagId) = \(Tag.id) WHERE \(RecipeTag.recipeId) = \(Recipe.id) AND \(Tag.name) COLLATE NOCASE LIKE \(bind: searchPatternWithWildcards))" : "")
            )
            \(includeFavorites ? "AND \(Recipe.isFavorite) = \(bind: true)" : "")
            ORDER BY \(raw: orderByFragment) \(raw: direction)
            """,
            as: Recipe.self)
        )
    }
    
    private func loadCategoryRecipesQueryWithoutSearch(categoryId: String, includeFavorites: Bool, sortOrder: RecipeListSortOrderSetting, sortDirection: RecipeListSortDirection) async throws {
        let direction = sortDirection.sqlSuffix
        
        // Build ORDER BY as plain SQL string fragment
        let orderByFragment: String = {
            switch sortOrder {
            case .byName: return "name COLLATE NOCASE \(direction)"
            case .bySource: return "source COLLATE NOCASE \(direction)"
            case .byDateModified: return "lastModifiedDate \(direction)"
            case .byDateCreated: return "createdDate \(direction)"
            case .byRating: return "rating \(direction)"
            case .byDifficulty: return "difficulty \(direction)"
            }
        }()
        
        try await $recipes.load(
            #sql(
            """
            SELECT DISTINCT \(Recipe.columns) FROM \(Recipe.self)
            INNER JOIN \(RecipeCategory.self) ON \(Recipe.id) = \(RecipeCategory.recipeId)
            WHERE \(RecipeCategory.categoryId) = \(bind: categoryId)
            \(includeFavorites ? "AND \(Recipe.isFavorite) = \(bind: true)" : "")
            ORDER BY \(raw: orderByFragment)
            """,
            as: Recipe.self)
        )
    }
    
    // MARK: - Course Query Methods
    
    private func loadCourseRecipesQuery(courseId: String, searchPattern: String?, includeFavorites: Bool, sortOrder: RecipeListSortOrderSetting, sortDirection: RecipeListSortDirection) async throws {
        let searchOptions = getSelectedSearchOptions()
        
        if let searchPattern = searchPattern {
            try await loadCourseRecipesQueryWithSearch(courseId: courseId, searchPattern: searchPattern, includeFavorites: includeFavorites, sortOrder: sortOrder, sortDirection: sortDirection, searchOptions: searchOptions)
        } else {
            try await loadCourseRecipesQueryWithoutSearch(courseId: courseId, includeFavorites: includeFavorites, sortOrder: sortOrder, sortDirection: sortDirection)
        }
    }
    
    private func loadCourseRecipesQueryWithSearch(courseId: String, searchPattern: String, includeFavorites: Bool, sortOrder: RecipeListSortOrderSetting, sortDirection: RecipeListSortDirection, searchOptions: Set<RecipeListSearchOptions>) async throws {
        let direction = sortDirection.sqlSuffix
        let orderByFragment: String = {
            switch sortOrder {
            case .byName: return "name COLLATE NOCASE"
            case .bySource: return "source COLLATE NOCASE"
            case .byDateModified: return "lastModifiedDate"
            case .byDateCreated: return "createdDate"
            case .byRating: return "rating"
            case .byDifficulty: return "difficulty"
            }
        }()
        
        let searchPatternWithWildcards = "%\(searchPattern)%"
        let hasName = searchOptions.contains(.name)
        let hasIntroduction = searchOptions.contains(.introduction)
        let hasCourse = searchOptions.contains(.course)
        let hasCategory = searchOptions.contains(.category)
        let hasTag = searchOptions.contains(.tag)
        let activeCount = [hasName, hasIntroduction, hasCourse, hasCategory, hasTag].filter { $0 }.count
        let needsFallback = activeCount == 0
        
        try await $recipes.load(
            #sql(
            """
            SELECT DISTINCT \(Recipe.columns) FROM \(Recipe.self)
            WHERE \(Recipe.courseId) = \(bind: courseId)
            AND (
                \(needsFallback || hasName ? "\(Recipe.name) COLLATE NOCASE LIKE \(bind: searchPatternWithWildcards)" : "")
                \(((needsFallback || hasName) && activeCount > (needsFallback ? 0 : 1)) ? " OR " : "")
                \(hasIntroduction ? "\(Recipe.introduction) COLLATE NOCASE LIKE \(bind: searchPatternWithWildcards)" : "")
                \(hasIntroduction && (hasCourse || hasCategory || hasTag) ? " OR " : "")
                \(hasCourse ? "EXISTS (SELECT 1 FROM \(Course.self) WHERE \(Course.id) = \(Recipe.courseId) AND \(Course.name) COLLATE NOCASE LIKE \(bind: searchPatternWithWildcards))" : "")
                \(hasCourse && (hasCategory || hasTag) ? " OR " : "")
                \(hasCategory ? "EXISTS (SELECT 1 FROM \(RecipeCategory.self) INNER JOIN \(Category.self) ON \(RecipeCategory.categoryId) = \(Category.id) WHERE \(RecipeCategory.recipeId) = \(Recipe.id) AND \(Category.name) COLLATE NOCASE LIKE \(bind: searchPatternWithWildcards))" : "")
                \(hasCategory && hasTag ? " OR " : "")
                \(hasTag ? "EXISTS (SELECT 1 FROM \(RecipeTag.self) INNER JOIN \(Tag.self) ON \(RecipeTag.tagId) = \(Tag.id) WHERE \(RecipeTag.recipeId) = \(Recipe.id) AND \(Tag.name) COLLATE NOCASE LIKE \(bind: searchPatternWithWildcards))" : "")
            )
            \(includeFavorites ? "AND \(Recipe.isFavorite) = \(bind: true)" : "")
            ORDER BY \(raw: orderByFragment) \(raw: direction)
            """,
            as: Recipe.self)
        )
    }
    
    private func loadCourseRecipesQueryWithoutSearch(courseId: String, includeFavorites: Bool, sortOrder: RecipeListSortOrderSetting, sortDirection: RecipeListSortDirection) async throws {
        let direction = sortDirection.sqlSuffix
        let orderByFragment: String = {
            switch sortOrder {
            case .byName: return "name COLLATE NOCASE \(direction)"
            case .bySource: return "source COLLATE NOCASE \(direction)"
            case .byDateModified: return "lastModifiedDate \(direction)"
            case .byDateCreated: return "createdDate \(direction)"
            case .byRating: return "rating \(direction)"
            case .byDifficulty: return "difficulty \(direction)"
            }
        }()
        
        try await $recipes.load(
            #sql(
            """
            SELECT DISTINCT \(Recipe.columns) FROM \(Recipe.self)
            WHERE \(Recipe.courseId) = \(bind: courseId)
            \(includeFavorites ? "AND \(Recipe.isFavorite) = \(bind: true)" : "")
            ORDER BY \(raw: orderByFragment)
            """,
            as: Recipe.self)
        )
    }
    
    // MARK: - Tag Query Methods
    
    private func loadTagRecipesQuery(tagId: String, searchPattern: String?, includeFavorites: Bool, sortOrder: RecipeListSortOrderSetting, sortDirection: RecipeListSortDirection) async throws {
        let searchOptions = getSelectedSearchOptions()
        
        if let searchPattern = searchPattern {
            try await loadTagRecipesQueryWithSearch(tagId: tagId, searchPattern: searchPattern, includeFavorites: includeFavorites, sortOrder: sortOrder, sortDirection: sortDirection, searchOptions: searchOptions)
        } else {
            try await loadTagRecipesQueryWithoutSearch(tagId: tagId, includeFavorites: includeFavorites, sortOrder: sortOrder, sortDirection: sortDirection)
        }
    }
    
    private func loadTagRecipesQueryWithSearch(tagId: String, searchPattern: String, includeFavorites: Bool, sortOrder: RecipeListSortOrderSetting, sortDirection: RecipeListSortDirection, searchOptions: Set<RecipeListSearchOptions>) async throws {
        let direction = sortDirection.sqlSuffix
        let orderByFragment: String = {
            switch sortOrder {
            case .byName: return "name COLLATE NOCASE"
            case .bySource: return "source COLLATE NOCASE"
            case .byDateModified: return "lastModifiedDate"
            case .byDateCreated: return "createdDate"
            case .byRating: return "rating"
            case .byDifficulty: return "difficulty"
            }
        }()
        
        let searchPatternWithWildcards = "%\(searchPattern)%"
        let hasName = searchOptions.contains(.name)
        let hasIntroduction = searchOptions.contains(.introduction)
        let hasCourse = searchOptions.contains(.course)
        let hasCategory = searchOptions.contains(.category)
        let hasTag = searchOptions.contains(.tag)
        let activeCount = [hasName, hasIntroduction, hasCourse, hasCategory, hasTag].filter { $0 }.count
        let needsFallback = activeCount == 0
        
        try await $recipes.load(
            #sql(
            """
            SELECT DISTINCT \(Recipe.columns) FROM \(Recipe.self)
            INNER JOIN \(RecipeTag.self) ON \(Recipe.id) = \(RecipeTag.recipeId)
            WHERE \(RecipeTag.tagId) = \(bind: tagId)
            AND (
                \(needsFallback || hasName ? "\(Recipe.name) COLLATE NOCASE LIKE \(bind: searchPatternWithWildcards)" : "")
                \(((needsFallback || hasName) && activeCount > (needsFallback ? 0 : 1)) ? " OR " : "")
                \(hasIntroduction ? "\(Recipe.introduction) COLLATE NOCASE LIKE \(bind: searchPatternWithWildcards)" : "")
                \(hasIntroduction && (hasCourse || hasCategory || hasTag) ? " OR " : "")
                \(hasCourse ? "EXISTS (SELECT 1 FROM \(Course.self) WHERE \(Course.id) = \(Recipe.courseId) AND \(Course.name) COLLATE NOCASE LIKE \(bind: searchPatternWithWildcards))" : "")
                \(hasCourse && (hasCategory || hasTag) ? " OR " : "")
                \(hasCategory ? "EXISTS (SELECT 1 FROM \(RecipeCategory.self) INNER JOIN \(Category.self) ON \(RecipeCategory.categoryId) = \(Category.id) WHERE \(RecipeCategory.recipeId) = \(Recipe.id) AND \(Category.name) COLLATE NOCASE LIKE \(bind: searchPatternWithWildcards))" : "")
                \(hasCategory && hasTag ? " OR " : "")
                \(hasTag ? "EXISTS (SELECT 1 FROM \(RecipeTag.self) AS rt2 INNER JOIN \(Tag.self) ON rt2.tagId = \(Tag.id) WHERE rt2.recipeId = \(Recipe.id) AND \(Tag.name) COLLATE NOCASE LIKE \(bind: searchPatternWithWildcards))" : "")
            )
            \(includeFavorites ? "AND \(Recipe.isFavorite) = \(bind: true)" : "")
            ORDER BY \(raw: orderByFragment) \(raw: direction)
            """,
            as: Recipe.self)
        )
    }
    
    private func loadTagRecipesQueryWithoutSearch(tagId: String, includeFavorites: Bool, sortOrder: RecipeListSortOrderSetting, sortDirection: RecipeListSortDirection) async throws {
        let direction = sortDirection.sqlSuffix
        let orderByFragment: String = {
            switch sortOrder {
            case .byName: return "name COLLATE NOCASE \(direction)"
            case .bySource: return "source COLLATE NOCASE \(direction)"
            case .byDateModified: return "lastModifiedDate \(direction)"
            case .byDateCreated: return "createdDate \(direction)"
            case .byRating: return "rating \(direction)"
            case .byDifficulty: return "difficulty \(direction)"
            }
        }()
        
        try await $recipes.load(
            #sql(
            """
            SELECT DISTINCT \(Recipe.columns) FROM \(Recipe.self)
            INNER JOIN \(RecipeTag.self) ON \(Recipe.id) = \(RecipeTag.recipeId)
            WHERE \(RecipeTag.tagId) = \(bind: tagId)
            \(includeFavorites ? "AND \(Recipe.isFavorite) = \(bind: true)" : "")
            ORDER BY \(raw: orderByFragment)
            """,
            as: Recipe.self)
        )
    }
    
    // Old method kept for reference - can be removed once confirmed working
    private func loadCategoryRecipesQuery_OLD(categoryId: String, searchPattern: String?, includeFavorites: Bool, sortOrder: RecipeListSortOrderSetting, sortDirection: RecipeListSortDirection) async throws {
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
            } else if let selectedId = selectedSidebarItemId {
                if selectedId.hasPrefix(categoryPrefix) {
                    let categoryId = String(selectedId.dropFirst(categoryPrefix.count))
                    try await loadCategoryRecipesQuery(categoryId: categoryId, searchPattern: searchPattern, includeFavorites: includeFavorites, sortOrder: recipeListSortOrder, sortDirection: recipeListSortDirection)
                } else if selectedId.hasPrefix(coursePrefix) {
                    let courseId = String(selectedId.dropFirst(coursePrefix.count))
                    try await loadCourseRecipesQuery(courseId: courseId, searchPattern: searchPattern, includeFavorites: includeFavorites, sortOrder: recipeListSortOrder, sortDirection: recipeListSortDirection)
                } else if selectedId.hasPrefix(tagPrefix) {
                    let tagId = String(selectedId.dropFirst(tagPrefix.count))
                    try await loadTagRecipesQuery(tagId: tagId, searchPattern: searchPattern, includeFavorites: includeFavorites, sortOrder: recipeListSortOrder, sortDirection: recipeListSortDirection)
                } else {
                    // Legacy: treat as category ID without prefix (for backward compatibility)
                    try await loadCategoryRecipesQuery(categoryId: selectedId, searchPattern: searchPattern, includeFavorites: includeFavorites, sortOrder: recipeListSortOrder, sortDirection: recipeListSortDirection)
                }
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
        
        // First try to find in the current filtered recipes list
        if let recipe = recipes.first(where: { $0.id == recipeId }) {
            return recipe
        }
        
        // If not found in filtered list (e.g., category removed when selected and Edit view open), fetch directly from database
        do {
            return try database.read { db in
                try Recipe.where { $0.id == recipeId }.fetchOne(db)
            }
        } catch {
            logger.error("Error fetching recipe for edit: \(error)")
            return nil
        }
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
    
    // MARK: - Category and Tag Management
    
    /// Adds a recipe to a category if it's not already associated
    func addRecipeToCategory(recipeId: String, categoryId: String) {
        do {
            try database.write { db in
                // Check if relationship already exists
                let existingRelationship = try RecipeCategory
                    .where { $0.recipeId == recipeId && $0.categoryId == categoryId }
                    .fetchOne(db)
                
                if existingRelationship == nil {
                    // Create relationship only if it doesn't already exist
                    let recipeCategory = RecipeCategory(
                        id: UUID().uuidString,
                        recipeId: recipeId,
                        categoryId: categoryId
                    )
                    try RecipeCategory.insert(recipeCategory).execute(db)
                    logger.info("Added recipe \(recipeId) to category \(categoryId)")
                } else {
                    logger.info("Recipe \(recipeId) is already in category \(categoryId)")
                }
            }
        } catch {
            logger.error("Error adding recipe to category: \(error)")
        }
    }
    
    /// Adds a recipe to a tag if it's not already associated
    func addRecipeToTag(recipeId: String, tagId: String) {
        do {
            try database.write { db in
                // Check if relationship already exists
                let existingRelationship = try RecipeTag
                    .where { $0.recipeId == recipeId && $0.tagId == tagId }
                    .fetchOne(db)
                
                if existingRelationship == nil {
                    // Create relationship only if it doesn't already exist
                    let recipeTag = RecipeTag(
                        id: UUID().uuidString,
                        recipeId: recipeId,
                        tagId: tagId
                    )
                    try RecipeTag.insert(recipeTag).execute(db)
                    logger.info("Added recipe \(recipeId) to tag \(tagId)")
                } else {
                    logger.info("Recipe \(recipeId) is already tagged with \(tagId)")
                }
            }
        } catch {
            logger.error("Error adding recipe to tag: \(error)")
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
    private let previewCourses: [Course]
    private let previewTags: [Tag]
    
    // MARK: - Override @FetchAll properties for preview
    override var recipes: [Recipe] { previewRecipes }
    override var categories: [Category] { previewCategories }
    override var courses: [Course] { previewCourses }
    override var tags: [Tag] { previewTags }
    
    // MARK: - Initialization
    init(previewData: (recipes: [Recipe], categories: [Category], courses: [Course], tags: [Tag])) {
        self.previewRecipes = previewData.recipes
        self.previewCategories = previewData.categories
        self.previewCourses = previewData.courses
        self.previewTags = previewData.tags
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
