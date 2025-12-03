//
//  RecipeNavigationSplitViewModel.swift
//  Salty
//
//  Created by Robert on 7/3/25.
//

import Foundation
import OSLog
import SQLiteData
import UniformTypeIdentifiers
#if os(macOS)
import WebKit
import AppKit
import ObjectiveC
import QuartzCore
import PDFKit
#endif

// MARK: - Notification Names

extension Notification.Name {
    static let exportSelectedRecipes = Notification.Name("exportSelectedRecipes")
    static let showImportFromFileSheet = Notification.Name("showImportFromFileSheet")
    static let showCreateFromWebSheet = Notification.Name("showCreateFromWebSheet")
    static let sheetStateChanged = Notification.Name("sheetStateChanged")
    static let showRecipeInfoInspector = Notification.Name("showRecipeInfoInspector")
    static let recipeSelectionChanged = Notification.Name("recipeSelectionChanged")
    static let exportSelectedRecipesAsHTML = Notification.Name("exportSelectedRecipesAsHTML")
    static let printSelectedRecipes = Notification.Name("printSelectedRecipes")
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
    var exportContentType: UTType = .saltyRecipe
    
    // HTML Export options
    var showingHTMLExportSettings = false
    var htmlExportOptions = HTMLExportOptions()
    var htmlExportRecipeId: String? // Store recipe ID for single recipe export
    
    // Print state (no longer needed for direct printing, but kept for potential future use)
    // var showingPrintView = false
    // var printRecipeId: String?
    // var printHTML: String?
    

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
        options.contains(.category) || options.contains(.course) || options.contains(.tags)
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
                        let hasName = searchOptions.contains(.name)
                        let hasIntroduction = searchOptions.contains(.introduction)
                        let hasIngredients = searchOptions.contains(.ingredients)
                        //let hasNotes = searchOptions.contains(.notes)
//                      //let hasVariations = searchOptions.contains(.variations)
                        // Combining for now to make easy, would like to separate some day...
                        let hasNotesOrVariations = searchOptions.contains(.notes)
                        
                        if hasName && hasIntroduction && hasIngredients && hasNotesOrVariations {
                            // All four selected (with notes/variations)
                            (#sql("\(recipe.name) COLLATE NOCASE LIKE \(bind: searchPattern)") || #sql("\(recipe.introduction) COLLATE NOCASE LIKE \(bind: searchPattern)") || #sql("\(recipe.ingredients) COLLATE NOCASE LIKE \(bind: searchPattern)") || #sql("\(recipe.notes) COLLATE NOCASE LIKE \(bind: searchPattern)") || #sql("\(recipe.variations) COLLATE NOCASE LIKE \(bind: searchPattern)")) && recipe.isFavorite == true
                        } else if hasName && hasIntroduction && hasIngredients {
                            // Name, introduction, and ingredients
                            (#sql("\(recipe.name) COLLATE NOCASE LIKE \(bind: searchPattern)") || #sql("\(recipe.introduction) COLLATE NOCASE LIKE \(bind: searchPattern)") || #sql("\(recipe.ingredients) COLLATE NOCASE LIKE \(bind: searchPattern)")) && recipe.isFavorite == true
                        } else if hasName && hasIntroduction && hasNotesOrVariations {
                            // Name, introduction, and notes/variations
                            (#sql("\(recipe.name) COLLATE NOCASE LIKE \(bind: searchPattern)") || #sql("\(recipe.introduction) COLLATE NOCASE LIKE \(bind: searchPattern)") || #sql("\(recipe.notes) COLLATE NOCASE LIKE \(bind: searchPattern)") || #sql("\(recipe.variations) COLLATE NOCASE LIKE \(bind: searchPattern)")) && recipe.isFavorite == true
                        } else if hasName && hasIngredients && hasNotesOrVariations {
                            // Name, ingredients, and notes/variations
                            (#sql("\(recipe.name) COLLATE NOCASE LIKE \(bind: searchPattern)") || #sql("\(recipe.ingredients) COLLATE NOCASE LIKE \(bind: searchPattern)") || #sql("\(recipe.notes) COLLATE NOCASE LIKE \(bind: searchPattern)") || #sql("\(recipe.variations) COLLATE NOCASE LIKE \(bind: searchPattern)")) && recipe.isFavorite == true
                        } else if hasIntroduction && hasIngredients && hasNotesOrVariations {
                            // Introduction, ingredients, and notes/variations
                            (#sql("\(recipe.introduction) COLLATE NOCASE LIKE \(bind: searchPattern)") || #sql("\(recipe.ingredients) COLLATE NOCASE LIKE \(bind: searchPattern)") || #sql("\(recipe.notes) COLLATE NOCASE LIKE \(bind: searchPattern)") || #sql("\(recipe.variations) COLLATE NOCASE LIKE \(bind: searchPattern)")) && recipe.isFavorite == true
                        } else if hasName && hasIntroduction {
                            // Name and introduction
                            (#sql("\(recipe.name) COLLATE NOCASE LIKE \(bind: searchPattern)") || #sql("\(recipe.introduction) COLLATE NOCASE LIKE \(bind: searchPattern)")) && recipe.isFavorite == true
                        } else if hasName && hasIngredients {
                            // Name and ingredients
                            (#sql("\(recipe.name) COLLATE NOCASE LIKE \(bind: searchPattern)") || #sql("\(recipe.ingredients) COLLATE NOCASE LIKE \(bind: searchPattern)")) && recipe.isFavorite == true
                        } else if hasName && hasNotesOrVariations {
                            // Name and notes/variations
                            (#sql("\(recipe.name) COLLATE NOCASE LIKE \(bind: searchPattern)") || #sql("\(recipe.notes) COLLATE NOCASE LIKE \(bind: searchPattern)") || #sql("\(recipe.variations) COLLATE NOCASE LIKE \(bind: searchPattern)")) && recipe.isFavorite == true
                        } else if hasIntroduction && hasIngredients {
                            // Introduction and ingredients
                            (#sql("\(recipe.introduction) COLLATE NOCASE LIKE \(bind: searchPattern)") || #sql("\(recipe.ingredients) COLLATE NOCASE LIKE \(bind: searchPattern)")) && recipe.isFavorite == true
                        } else if hasIntroduction && hasNotesOrVariations {
                            // Introduction and notes/variations
                            (#sql("\(recipe.introduction) COLLATE NOCASE LIKE \(bind: searchPattern)") || #sql("\(recipe.notes) COLLATE NOCASE LIKE \(bind: searchPattern)") || #sql("\(recipe.variations) COLLATE NOCASE LIKE \(bind: searchPattern)")) && recipe.isFavorite == true
                        } else if hasIngredients && hasNotesOrVariations {
                            // Ingredients and notes/variations
                            (#sql("\(recipe.ingredients) COLLATE NOCASE LIKE \(bind: searchPattern)") || #sql("\(recipe.notes) COLLATE NOCASE LIKE \(bind: searchPattern)") || #sql("\(recipe.variations) COLLATE NOCASE LIKE \(bind: searchPattern)")) && recipe.isFavorite == true
                        } else if hasName {
                            // Only name selected
                            #sql("\(recipe.name) COLLATE NOCASE LIKE \(bind: searchPattern)") && recipe.isFavorite == true
                        } else if hasIntroduction {
                            // Only introduction selected
                            #sql("\(recipe.introduction) COLLATE NOCASE LIKE \(bind: searchPattern)") && recipe.isFavorite == true
                        } else if hasIngredients {
                            // Only ingredients selected
                            #sql("\(recipe.ingredients) COLLATE NOCASE LIKE \(bind: searchPattern)") && recipe.isFavorite == true
                        } else if hasNotesOrVariations {
                            // Only notes/variations selected - search both
                            (#sql("\(recipe.notes) COLLATE NOCASE LIKE \(bind: searchPattern)") || #sql("\(recipe.variations) COLLATE NOCASE LIKE \(bind: searchPattern)")) && recipe.isFavorite == true
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
                        let hasName = searchOptions.contains(.name)
                        let hasIntroduction = searchOptions.contains(.introduction)
                        let hasIngredients = searchOptions.contains(.ingredients)
                        //let hasNotes = searchOptions.contains(.notes)
                        //let hasVariations = searchOptions.contains(.variations)
                        // Combining to make easy for now; would like to separate some day:
                        let hasNotesOrVariations = searchOptions.contains(.notes)
                        
                        if hasName && hasIntroduction && hasIngredients && hasNotesOrVariations {
                            // All four selected (with notes/variations)
                            #sql("\(recipe.name) COLLATE NOCASE LIKE \(bind: searchPattern)") || #sql("\(recipe.introduction) COLLATE NOCASE LIKE \(bind: searchPattern)") || #sql("\(recipe.ingredients) COLLATE NOCASE LIKE \(bind: searchPattern)") || #sql("\(recipe.notes) COLLATE NOCASE LIKE \(bind: searchPattern)") || #sql("\(recipe.variations) COLLATE NOCASE LIKE \(bind: searchPattern)")
                        } else if hasName && hasIntroduction && hasIngredients {
                            // Name, introduction, and ingredients
                            #sql("\(recipe.name) COLLATE NOCASE LIKE \(bind: searchPattern)") || #sql("\(recipe.introduction) COLLATE NOCASE LIKE \(bind: searchPattern)") || #sql("\(recipe.ingredients) COLLATE NOCASE LIKE \(bind: searchPattern)")
                        } else if hasName && hasIntroduction && hasNotesOrVariations {
                            // Name, introduction, and notes/variations
                            #sql("\(recipe.name) COLLATE NOCASE LIKE \(bind: searchPattern)") || #sql("\(recipe.introduction) COLLATE NOCASE LIKE \(bind: searchPattern)") || #sql("\(recipe.notes) COLLATE NOCASE LIKE \(bind: searchPattern)") || #sql("\(recipe.variations) COLLATE NOCASE LIKE \(bind: searchPattern)")
                        } else if hasName && hasIngredients && hasNotesOrVariations {
                            // Name, ingredients, and notes/variations
                            #sql("\(recipe.name) COLLATE NOCASE LIKE \(bind: searchPattern)") || #sql("\(recipe.ingredients) COLLATE NOCASE LIKE \(bind: searchPattern)") || #sql("\(recipe.notes) COLLATE NOCASE LIKE \(bind: searchPattern)") || #sql("\(recipe.variations) COLLATE NOCASE LIKE \(bind: searchPattern)")
                        } else if hasIntroduction && hasIngredients && hasNotesOrVariations {
                            // Introduction, ingredients, and notes/variations
                            #sql("\(recipe.introduction) COLLATE NOCASE LIKE \(bind: searchPattern)") || #sql("\(recipe.ingredients) COLLATE NOCASE LIKE \(bind: searchPattern)") || #sql("\(recipe.notes) COLLATE NOCASE LIKE \(bind: searchPattern)") || #sql("\(recipe.variations) COLLATE NOCASE LIKE \(bind: searchPattern)")
                        } else if hasName && hasIntroduction {
                            // Name and introduction
                            #sql("\(recipe.name) COLLATE NOCASE LIKE \(bind: searchPattern)") || #sql("\(recipe.introduction) COLLATE NOCASE LIKE \(bind: searchPattern)")
                        } else if hasName && hasIngredients {
                            // Name and ingredients
                            #sql("\(recipe.name) COLLATE NOCASE LIKE \(bind: searchPattern)") || #sql("\(recipe.ingredients) COLLATE NOCASE LIKE \(bind: searchPattern)")
                        } else if hasName && hasNotesOrVariations {
                            // Name and notes/variations
                            #sql("\(recipe.name) COLLATE NOCASE LIKE \(bind: searchPattern)") || #sql("\(recipe.notes) COLLATE NOCASE LIKE \(bind: searchPattern)") || #sql("\(recipe.variations) COLLATE NOCASE LIKE \(bind: searchPattern)")
                        } else if hasIntroduction && hasIngredients {
                            // Introduction and ingredients
                            #sql("\(recipe.introduction) COLLATE NOCASE LIKE \(bind: searchPattern)") || #sql("\(recipe.ingredients) COLLATE NOCASE LIKE \(bind: searchPattern)")
                        } else if hasIntroduction && hasNotesOrVariations {
                            // Introduction and notes/variations
                            #sql("\(recipe.introduction) COLLATE NOCASE LIKE \(bind: searchPattern)") || #sql("\(recipe.notes) COLLATE NOCASE LIKE \(bind: searchPattern)") || #sql("\(recipe.variations) COLLATE NOCASE LIKE \(bind: searchPattern)")
                        } else if hasIngredients && hasNotesOrVariations {
                            // Ingredients and notes/variations
                            #sql("\(recipe.ingredients) COLLATE NOCASE LIKE \(bind: searchPattern)") || #sql("\(recipe.notes) COLLATE NOCASE LIKE \(bind: searchPattern)") || #sql("\(recipe.variations) COLLATE NOCASE LIKE \(bind: searchPattern)")
                        } else if hasName {
                            // Only name selected
                            #sql("\(recipe.name) COLLATE NOCASE LIKE \(bind: searchPattern)")
                        } else if hasIntroduction {
                            // Only introduction selected
                            #sql("\(recipe.introduction) COLLATE NOCASE LIKE \(bind: searchPattern)")
                        } else if hasIngredients {
                            // Only ingredients selected
                            #sql("\(recipe.ingredients) COLLATE NOCASE LIKE \(bind: searchPattern)")
                        } else if hasNotesOrVariations {
                            // Only notes/variations selected - search both
                            #sql("\(recipe.notes) COLLATE NOCASE LIKE \(bind: searchPattern)") || #sql("\(recipe.variations) COLLATE NOCASE LIKE \(bind: searchPattern)")
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
        let hasTag = searchOptions.contains(.tags)
        let hasIngredients = searchOptions.contains(.ingredients)
        
        // Build WHERE clause conditionally - only include bind: for active conditions
        // Use if-else to generate different SQL strings so bind: only appears in executed paths
        if hasTag && !hasName && !hasIntroduction && !hasCourse && !hasCategory && !hasIngredients {
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
        } else if hasName && !hasIntroduction && !hasCourse && !hasCategory && !hasTag && !hasIngredients {
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
            // Multiple conditions - route to general handler which handles all combinations
            try await loadAllRecipesQueryWithJoinsGeneral(searchPattern: searchPattern, includeFavorites: includeFavorites, sortOrder: sortOrder, sortDirection: sortDirection, searchOptions: searchOptions, orderByFragment: orderByFragment, direction: direction, searchPatternWithWildcards: searchPatternWithWildcards)
        }
    }
    
    // Helper method for general case with multiple search conditions
    // Uses explicit condition building to avoid bind: in inactive branches
    private func loadAllRecipesQueryWithJoinsGeneral(searchPattern: String, includeFavorites: Bool, sortOrder: RecipeListSortOrderSetting, sortDirection: RecipeListSortDirection, searchOptions: Set<RecipeListSearchOptions>, orderByFragment: String, direction: String, searchPatternWithWildcards: String) async throws {
        let hasName = searchOptions.contains(.name)
        let hasIntroduction = searchOptions.contains(.introduction)
        let hasCourse = searchOptions.contains(.course)
        let hasCategory = searchOptions.contains(.category)
        let hasTag = searchOptions.contains(.tags)
        let hasIngredients = searchOptions.contains(.ingredients)
        //let hasNotes = searchOptions.contains(.notes)
        //let hasVariations = searchOptions.contains(.variations)
        // Combining to make easy for now; would like to separate some day:
        let hasNotesOrVariations = searchOptions.contains(.notes)
        
        // Build combination identifier
        let combo = (hasName ? 1 : 0) | (hasIntroduction ? 2 : 0) | (hasCourse ? 4 : 0) | (hasCategory ? 8 : 0) | (hasTag ? 16 : 0) | (hasIngredients ? 32 : 0) | (hasNotesOrVariations ? 64 : 0)
        
        // Handle all combinations explicitly
        switch combo {
        case 33: // Name + Ingredients
            try await $recipes.load(
                #sql(
                """
                SELECT DISTINCT \(Recipe.columns) FROM \(Recipe.self)
                WHERE (
                    \(Recipe.name) COLLATE NOCASE LIKE \(bind: searchPatternWithWildcards) OR
                    \(Recipe.ingredients) COLLATE NOCASE LIKE \(bind: searchPatternWithWildcards)
                )
                \(includeFavorites ? "AND \(Recipe.isFavorite) = \(bind: true)" : "")
                ORDER BY \(raw: orderByFragment) \(raw: direction)
                """,
                as: Recipe.self)
            )
        case 3: // Name + Introduction
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
        case 35: // Name + Introduction + Ingredients
            try await $recipes.load(
                #sql(
                """
                SELECT DISTINCT \(Recipe.columns) FROM \(Recipe.self)
                WHERE (
                    \(Recipe.name) COLLATE NOCASE LIKE \(bind: searchPatternWithWildcards) OR
                    \(Recipe.introduction) COLLATE NOCASE LIKE \(bind: searchPatternWithWildcards) OR
                    \(Recipe.ingredients) COLLATE NOCASE LIKE \(bind: searchPatternWithWildcards)
                )
                \(includeFavorites ? "AND \(Recipe.isFavorite) = \(bind: true)" : "")
                ORDER BY \(raw: orderByFragment) \(raw: direction)
                """,
                as: Recipe.self)
            )
        case 49: // Name + Ingredients + Tag
            try await $recipes.load(
                #sql(
                """
                SELECT DISTINCT \(Recipe.columns) FROM \(Recipe.self)
                WHERE (
                    \(Recipe.name) COLLATE NOCASE LIKE \(bind: searchPatternWithWildcards) OR
                    EXISTS (SELECT 1 FROM \(RecipeTag.self) INNER JOIN \(Tag.self) ON \(RecipeTag.tagId) = \(Tag.id) WHERE \(RecipeTag.recipeId) = \(Recipe.id) AND \(Tag.name) COLLATE NOCASE LIKE \(bind: searchPatternWithWildcards)) OR
                    \(Recipe.ingredients) COLLATE NOCASE LIKE \(bind: searchPatternWithWildcards)
                )
                \(includeFavorites ? "AND \(Recipe.isFavorite) = \(bind: true)" : "")
                ORDER BY \(raw: orderByFragment) \(raw: direction)
                """,
                as: Recipe.self)
            )
        case 51: // Name + Introduction + Ingredients + Tag
            try await $recipes.load(
                #sql(
                """
                SELECT DISTINCT \(Recipe.columns) FROM \(Recipe.self)
                WHERE (
                    \(Recipe.name) COLLATE NOCASE LIKE \(bind: searchPatternWithWildcards) OR
                    \(Recipe.introduction) COLLATE NOCASE LIKE \(bind: searchPatternWithWildcards) OR
                    EXISTS (SELECT 1 FROM \(RecipeTag.self) INNER JOIN \(Tag.self) ON \(RecipeTag.tagId) = \(Tag.id) WHERE \(RecipeTag.recipeId) = \(Recipe.id) AND \(Tag.name) COLLATE NOCASE LIKE \(bind: searchPatternWithWildcards)) OR
                    \(Recipe.ingredients) COLLATE NOCASE LIKE \(bind: searchPatternWithWildcards)
                )
                \(includeFavorites ? "AND \(Recipe.isFavorite) = \(bind: true)" : "")
                ORDER BY \(raw: orderByFragment) \(raw: direction)
                """,
                as: Recipe.self)
            )
        case 17: // Name + Tag
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
        case 19: // Name + Introduction + Tag
            try await $recipes.load(
                #sql(
                """
                SELECT DISTINCT \(Recipe.columns) FROM \(Recipe.self)
                WHERE (
                    \(Recipe.name) COLLATE NOCASE LIKE \(bind: searchPatternWithWildcards) OR
                    \(Recipe.introduction) COLLATE NOCASE LIKE \(bind: searchPatternWithWildcards) OR
                    EXISTS (SELECT 1 FROM \(RecipeTag.self) INNER JOIN \(Tag.self) ON \(RecipeTag.tagId) = \(Tag.id) WHERE \(RecipeTag.recipeId) = \(Recipe.id) AND \(Tag.name) COLLATE NOCASE LIKE \(bind: searchPatternWithWildcards))
                )
                \(includeFavorites ? "AND \(Recipe.isFavorite) = \(bind: true)" : "")
                ORDER BY \(raw: orderByFragment) \(raw: direction)
                """,
                as: Recipe.self)
            )
        default:
            // For other complex combinations, handle them explicitly
            try await loadAllRecipesQueryWithJoinsFallback(searchPatternWithWildcards: searchPatternWithWildcards, includeFavorites: includeFavorites, orderByFragment: orderByFragment, direction: direction, hasName: hasName, hasIntroduction: hasIntroduction, hasCourse: hasCourse, hasCategory: hasCategory, hasTag: hasTag, hasIngredients: hasIngredients, hasNotesOrVariations: hasNotesOrVariations)
        }
    }
    
    private func loadAllRecipesQueryWithJoinsFallback(searchPatternWithWildcards: String, includeFavorites: Bool, orderByFragment: String, direction: String, hasName: Bool, hasIntroduction: Bool, hasCourse: Bool, hasCategory: Bool, hasTag: Bool, hasIngredients: Bool, hasNotesOrVariations: Bool) async throws {
        // Handle remaining complex combinations explicitly
        // For cases with course/category, we need to handle them case by case
        // Default to name-only search as fallback to avoid SQL errors
        // (Ideally we'd handle all combinations, but that would require many explicit cases)
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
        let hasTag = searchOptions.contains(.tags)
        let hasIngredients = searchOptions.contains(.ingredients)
        //let hasNotes = searchOptions.contains(.notes)
        //let hasVariations = searchOptions.contains(.variations)
        // Combining to make easy for now; would like to separate some day:
        let hasNotesOrVariations = searchOptions.contains(.notes)
        
        // Build WHERE clause conditions - only include active options
        // Use a helper function approach to avoid bind: in inactive branches
        if hasName && !hasIntroduction && !hasCourse && !hasCategory && !hasTag && !hasIngredients && !hasNotesOrVariations {
            // Only name selected
            try await $recipes.load(
                #sql(
                """
                SELECT DISTINCT \(Recipe.columns) FROM \(Recipe.self)
                INNER JOIN \(RecipeCategory.self) ON \(Recipe.id) = \(RecipeCategory.recipeId)
                WHERE \(RecipeCategory.categoryId) = \(bind: categoryId)
                AND \(Recipe.name) COLLATE NOCASE LIKE \(bind: searchPatternWithWildcards)
                \(includeFavorites ? "AND \(Recipe.isFavorite) = \(bind: true)" : "")
                ORDER BY \(raw: orderByFragment) \(raw: direction)
                """,
                as: Recipe.self)
            )
        } else {
            // Build conditions array and join with OR
            // We need to handle multiple conditions - use a more flexible approach
            try await loadCategoryRecipesQueryWithSearchGeneral(categoryId: categoryId, searchPatternWithWildcards: searchPatternWithWildcards, includeFavorites: includeFavorites, orderByFragment: orderByFragment, direction: direction, hasName: hasName, hasIntroduction: hasIntroduction, hasCourse: hasCourse, hasCategory: hasCategory, hasTag: hasTag, hasIngredients: hasIngredients, hasNotesOrVariations: hasNotesOrVariations)
        }
    }
    
    private func loadCategoryRecipesQueryWithSearchGeneral(categoryId: String, searchPatternWithWildcards: String, includeFavorites: Bool, orderByFragment: String, direction: String, hasName: Bool, hasIntroduction: Bool, hasCourse: Bool, hasCategory: Bool, hasTag: Bool, hasIngredients: Bool, hasNotesOrVariations: Bool) async throws {
        // Count active options - use actual values, not "effective" name
        let activeOptions = [hasName, hasIntroduction, hasCourse, hasCategory, hasTag, hasIngredients, hasNotesOrVariations].filter { $0 }
        let activeCount = activeOptions.count
        
        // Default to name only if NO options are selected at all
        let shouldUseNameDefault = activeCount == 0
        
        // Handle each case explicitly to avoid bind: in empty strings
        if activeCount == 1 {
            if hasName {
                // Only name - already handled in parent function, but handle here too for completeness
                try await $recipes.load(
                    #sql(
                    """
                    SELECT DISTINCT \(Recipe.columns) FROM \(Recipe.self)
                    INNER JOIN \(RecipeCategory.self) ON \(Recipe.id) = \(RecipeCategory.recipeId)
                    WHERE \(RecipeCategory.categoryId) = \(bind: categoryId)
                    AND \(Recipe.name) COLLATE NOCASE LIKE \(bind: searchPatternWithWildcards)
                    \(includeFavorites ? "AND \(Recipe.isFavorite) = \(bind: true)" : "")
                    ORDER BY \(raw: orderByFragment) \(raw: direction)
                    """,
                    as: Recipe.self)
                )
            } else if hasIntroduction {
                try await $recipes.load(
                    #sql(
                    """
                    SELECT DISTINCT \(Recipe.columns) FROM \(Recipe.self)
                    INNER JOIN \(RecipeCategory.self) ON \(Recipe.id) = \(RecipeCategory.recipeId)
                    WHERE \(RecipeCategory.categoryId) = \(bind: categoryId)
                    AND \(Recipe.introduction) COLLATE NOCASE LIKE \(bind: searchPatternWithWildcards)
                    \(includeFavorites ? "AND \(Recipe.isFavorite) = \(bind: true)" : "")
                    ORDER BY \(raw: orderByFragment) \(raw: direction)
                    """,
                    as: Recipe.self)
                )
            } else if hasIngredients {
                try await $recipes.load(
                    #sql(
                    """
                    SELECT DISTINCT \(Recipe.columns) FROM \(Recipe.self)
                    INNER JOIN \(RecipeCategory.self) ON \(Recipe.id) = \(RecipeCategory.recipeId)
                    WHERE \(RecipeCategory.categoryId) = \(bind: categoryId)
                    AND \(Recipe.ingredients) COLLATE NOCASE LIKE \(bind: searchPatternWithWildcards)
                    \(includeFavorites ? "AND \(Recipe.isFavorite) = \(bind: true)" : "")
                    ORDER BY \(raw: orderByFragment) \(raw: direction)
                    """,
                    as: Recipe.self)
                )
            } else if hasNotesOrVariations {
                try await $recipes.load(
                    #sql(
                    """
                    SELECT DISTINCT \(Recipe.columns) FROM \(Recipe.self)
                    INNER JOIN \(RecipeCategory.self) ON \(Recipe.id) = \(RecipeCategory.recipeId)
                    WHERE \(RecipeCategory.categoryId) = \(bind: categoryId)
                    AND (\(Recipe.notes) COLLATE NOCASE LIKE \(bind: searchPatternWithWildcards) OR \(Recipe.variations) COLLATE NOCASE LIKE \(bind: searchPatternWithWildcards))
                    \(includeFavorites ? "AND \(Recipe.isFavorite) = \(bind: true)" : "")
                    ORDER BY \(raw: orderByFragment) \(raw: direction)
                    """,
                    as: Recipe.self)
                )
            } else if shouldUseNameDefault {
                // Fallback: if nothing selected, default to name
                try await $recipes.load(
                    #sql(
                    """
                    SELECT DISTINCT \(Recipe.columns) FROM \(Recipe.self)
                    INNER JOIN \(RecipeCategory.self) ON \(Recipe.id) = \(RecipeCategory.recipeId)
                    WHERE \(RecipeCategory.categoryId) = \(bind: categoryId)
                    AND \(Recipe.name) COLLATE NOCASE LIKE \(bind: searchPatternWithWildcards)
                    \(includeFavorites ? "AND \(Recipe.isFavorite) = \(bind: true)" : "")
                    ORDER BY \(raw: orderByFragment) \(raw: direction)
                    """,
                    as: Recipe.self)
                )
            }
        } else if activeCount == 2 {
            // Two conditions - handle explicitly
            if hasName && hasIntroduction {
                try await $recipes.load(
                    #sql(
                    """
                    SELECT DISTINCT \(Recipe.columns) FROM \(Recipe.self)
                    INNER JOIN \(RecipeCategory.self) ON \(Recipe.id) = \(RecipeCategory.recipeId)
                    WHERE \(RecipeCategory.categoryId) = \(bind: categoryId)
                    AND (\(Recipe.name) COLLATE NOCASE LIKE \(bind: searchPatternWithWildcards) OR \(Recipe.introduction) COLLATE NOCASE LIKE \(bind: searchPatternWithWildcards))
                    \(includeFavorites ? "AND \(Recipe.isFavorite) = \(bind: true)" : "")
                    ORDER BY \(raw: orderByFragment) \(raw: direction)
                    """,
                    as: Recipe.self)
                )
            } else if hasName && hasIngredients {
                try await $recipes.load(
                    #sql(
                    """
                    SELECT DISTINCT \(Recipe.columns) FROM \(Recipe.self)
                    INNER JOIN \(RecipeCategory.self) ON \(Recipe.id) = \(RecipeCategory.recipeId)
                    WHERE \(RecipeCategory.categoryId) = \(bind: categoryId)
                    AND (\(Recipe.name) COLLATE NOCASE LIKE \(bind: searchPatternWithWildcards) OR \(Recipe.ingredients) COLLATE NOCASE LIKE \(bind: searchPatternWithWildcards))
                    \(includeFavorites ? "AND \(Recipe.isFavorite) = \(bind: true)" : "")
                    ORDER BY \(raw: orderByFragment) \(raw: direction)
                    """,
                    as: Recipe.self)
                )
            } else if hasIntroduction && hasIngredients {
                try await $recipes.load(
                    #sql(
                    """
                    SELECT DISTINCT \(Recipe.columns) FROM \(Recipe.self)
                    INNER JOIN \(RecipeCategory.self) ON \(Recipe.id) = \(RecipeCategory.recipeId)
                    WHERE \(RecipeCategory.categoryId) = \(bind: categoryId)
                    AND (\(Recipe.introduction) COLLATE NOCASE LIKE \(bind: searchPatternWithWildcards) OR \(Recipe.ingredients) COLLATE NOCASE LIKE \(bind: searchPatternWithWildcards))
                    \(includeFavorites ? "AND \(Recipe.isFavorite) = \(bind: true)" : "")
                    ORDER BY \(raw: orderByFragment) \(raw: direction)
                    """,
                    as: Recipe.self)
                )
            } else {
                // Fallback for other 2-option combinations
                try await loadCategoryRecipesQueryWithSearchComplex(categoryId: categoryId, searchPatternWithWildcards: searchPatternWithWildcards, includeFavorites: includeFavorites, orderByFragment: orderByFragment, direction: direction, hasName: hasName, hasIntroduction: hasIntroduction, hasCourse: hasCourse, hasCategory: hasCategory, hasTag: hasTag, hasIngredients: hasIngredients, hasNotesOrVariations: hasNotesOrVariations)
            }
        } else {
            // Three or more conditions - use complex handler
            try await loadCategoryRecipesQueryWithSearchComplex(categoryId: categoryId, searchPatternWithWildcards: searchPatternWithWildcards, includeFavorites: includeFavorites, orderByFragment: orderByFragment, direction: direction, hasName: hasName, hasIntroduction: hasIntroduction, hasCourse: hasCourse, hasCategory: hasCategory, hasTag: hasTag, hasIngredients: hasIngredients, hasNotesOrVariations: hasNotesOrVariations)
        }
    }
    
    private func loadCategoryRecipesQueryWithSearchComplex(categoryId: String, searchPatternWithWildcards: String, includeFavorites: Bool, orderByFragment: String, direction: String, hasName: Bool, hasIntroduction: Bool, hasCourse: Bool, hasCategory: Bool, hasTag: Bool, hasIngredients: Bool, hasNotesOrVariations: Bool) async throws {
        // Handle all combinations explicitly - build queries for each specific combination
        // to avoid bind: in inactive branches
        
        // Count which fields are active
        let activeFields = [hasName, hasIntroduction, hasCourse, hasCategory, hasTag, hasIngredients, hasNotesOrVariations]
        let activeCount = activeFields.filter { $0 }.count
        
        // Handle common combinations explicitly
        if hasName && hasIntroduction && hasIngredients && !hasCourse && !hasCategory && !hasTag {
            // Name + Introduction + Ingredients
            try await $recipes.load(
                #sql(
                """
                SELECT DISTINCT \(Recipe.columns) FROM \(Recipe.self)
                INNER JOIN \(RecipeCategory.self) ON \(Recipe.id) = \(RecipeCategory.recipeId)
                WHERE \(RecipeCategory.categoryId) = \(bind: categoryId)
                AND (\(Recipe.name) COLLATE NOCASE LIKE \(bind: searchPatternWithWildcards) OR \(Recipe.introduction) COLLATE NOCASE LIKE \(bind: searchPatternWithWildcards) OR \(Recipe.ingredients) COLLATE NOCASE LIKE \(bind: searchPatternWithWildcards))
                \(includeFavorites ? "AND \(Recipe.isFavorite) = \(bind: true)" : "")
                ORDER BY \(raw: orderByFragment) \(raw: direction)
                """,
                as: Recipe.self)
            )
        } else if hasName && hasIngredients && !hasIntroduction && !hasCourse && !hasCategory && !hasTag {
            // Name + Ingredients only
            try await $recipes.load(
                #sql(
                """
                SELECT DISTINCT \(Recipe.columns) FROM \(Recipe.self)
                INNER JOIN \(RecipeCategory.self) ON \(Recipe.id) = \(RecipeCategory.recipeId)
                WHERE \(RecipeCategory.categoryId) = \(bind: categoryId)
                AND (\(Recipe.name) COLLATE NOCASE LIKE \(bind: searchPatternWithWildcards) OR \(Recipe.ingredients) COLLATE NOCASE LIKE \(bind: searchPatternWithWildcards))
                \(includeFavorites ? "AND \(Recipe.isFavorite) = \(bind: true)" : "")
                ORDER BY \(raw: orderByFragment) \(raw: direction)
                """,
                as: Recipe.self)
            )
        } else if hasName && hasIntroduction && !hasCourse && !hasCategory && !hasTag && !hasIngredients {
            // Name + Introduction only
            try await $recipes.load(
                #sql(
                """
                SELECT DISTINCT \(Recipe.columns) FROM \(Recipe.self)
                INNER JOIN \(RecipeCategory.self) ON \(Recipe.id) = \(RecipeCategory.recipeId)
                WHERE \(RecipeCategory.categoryId) = \(bind: categoryId)
                AND (\(Recipe.name) COLLATE NOCASE LIKE \(bind: searchPatternWithWildcards) OR \(Recipe.introduction) COLLATE NOCASE LIKE \(bind: searchPatternWithWildcards))
                \(includeFavorites ? "AND \(Recipe.isFavorite) = \(bind: true)" : "")
                ORDER BY \(raw: orderByFragment) \(raw: direction)
                """,
                as: Recipe.self)
            )
        } else {
            // Handle all other combinations - build query with all active fields
            // Use explicit if-else chains to ensure bind: only in active branches
            try await loadCategoryRecipesQueryWithSearchAllFields(categoryId: categoryId, searchPatternWithWildcards: searchPatternWithWildcards, includeFavorites: includeFavorites, orderByFragment: orderByFragment, direction: direction, hasName: hasName, hasIntroduction: hasIntroduction, hasCourse: hasCourse, hasCategory: hasCategory, hasTag: hasTag, hasIngredients: hasIngredients, hasNotesOrVariations: hasNotesOrVariations)
        }
    }
    
    private func loadCategoryRecipesQueryWithSearchAllFields(categoryId: String, searchPatternWithWildcards: String, includeFavorites: Bool, orderByFragment: String, direction: String, hasName: Bool, hasIntroduction: Bool, hasCourse: Bool, hasCategory: Bool, hasTag: Bool, hasIngredients: Bool, hasNotesOrVariations: Bool) async throws {
        // Build WHERE clause parts based on active options
        // We need to handle this carefully to avoid bind: in inactive branches
        // Since we can't build strings with bind: outside #sql, we'll use nested conditionals
        
        // Determine which fields are active and build appropriate query
        if hasName {
            if hasIntroduction {
                if hasIngredients {
                    // Name + Introduction + Ingredients (and possibly others)
                    if hasCourse || hasCategory || hasTag {
                        // Has JOINs needed fields - use comprehensive query
                        try await loadCategoryRecipesQueryWithAllOptions(categoryId: categoryId, searchPatternWithWildcards: searchPatternWithWildcards, includeFavorites: includeFavorites, orderByFragment: orderByFragment, direction: direction, hasName: true, hasIntroduction: true, hasCourse: hasCourse, hasCategory: hasCategory, hasTag: hasTag, hasIngredients: true)
                    } else {
                        // Name + Introduction + Ingredients only
                        try await $recipes.load(
                            #sql(
                            """
                            SELECT DISTINCT \(Recipe.columns) FROM \(Recipe.self)
                            INNER JOIN \(RecipeCategory.self) ON \(Recipe.id) = \(RecipeCategory.recipeId)
                            WHERE \(RecipeCategory.categoryId) = \(bind: categoryId)
                            AND (\(Recipe.name) COLLATE NOCASE LIKE \(bind: searchPatternWithWildcards) OR \(Recipe.introduction) COLLATE NOCASE LIKE \(bind: searchPatternWithWildcards) OR \(Recipe.ingredients) COLLATE NOCASE LIKE \(bind: searchPatternWithWildcards))
                            \(includeFavorites ? "AND \(Recipe.isFavorite) = \(bind: true)" : "")
                            ORDER BY \(raw: orderByFragment) \(raw: direction)
                            """,
                            as: Recipe.self)
                        )
                    }
                } else {
                    // Name + Introduction (and possibly others)
                    if hasCourse || hasCategory || hasTag {
                        try await loadCategoryRecipesQueryWithAllOptions(categoryId: categoryId, searchPatternWithWildcards: searchPatternWithWildcards, includeFavorites: includeFavorites, orderByFragment: orderByFragment, direction: direction, hasName: true, hasIntroduction: true, hasCourse: hasCourse, hasCategory: hasCategory, hasTag: hasTag, hasIngredients: false)
                    } else {
                        // Name + Introduction only
                        try await $recipes.load(
                            #sql(
                            """
                            SELECT DISTINCT \(Recipe.columns) FROM \(Recipe.self)
                            INNER JOIN \(RecipeCategory.self) ON \(Recipe.id) = \(RecipeCategory.recipeId)
                            WHERE \(RecipeCategory.categoryId) = \(bind: categoryId)
                            AND (\(Recipe.name) COLLATE NOCASE LIKE \(bind: searchPatternWithWildcards) OR \(Recipe.introduction) COLLATE NOCASE LIKE \(bind: searchPatternWithWildcards))
                            \(includeFavorites ? "AND \(Recipe.isFavorite) = \(bind: true)" : "")
                            ORDER BY \(raw: orderByFragment) \(raw: direction)
                            """,
                            as: Recipe.self)
                        )
                    }
                }
            } else if hasIngredients {
                // Name + Ingredients (and possibly others)
                if hasCourse || hasCategory || hasTag {
                    try await loadCategoryRecipesQueryWithAllOptions(categoryId: categoryId, searchPatternWithWildcards: searchPatternWithWildcards, includeFavorites: includeFavorites, orderByFragment: orderByFragment, direction: direction, hasName: true, hasIntroduction: false, hasCourse: hasCourse, hasCategory: hasCategory, hasTag: hasTag, hasIngredients: true)
                } else {
                    // Name + Ingredients only
                    try await $recipes.load(
                        #sql(
                        """
                        SELECT DISTINCT \(Recipe.columns) FROM \(Recipe.self)
                        INNER JOIN \(RecipeCategory.self) ON \(Recipe.id) = \(RecipeCategory.recipeId)
                        WHERE \(RecipeCategory.categoryId) = \(bind: categoryId)
                        AND (\(Recipe.name) COLLATE NOCASE LIKE \(bind: searchPatternWithWildcards) OR \(Recipe.ingredients) COLLATE NOCASE LIKE \(bind: searchPatternWithWildcards))
                        \(includeFavorites ? "AND \(Recipe.isFavorite) = \(bind: true)" : "")
                        ORDER BY \(raw: orderByFragment) \(raw: direction)
                        """,
                        as: Recipe.self)
                    )
                }
            } else {
                // Name + other fields that need JOINs
                try await loadCategoryRecipesQueryWithAllOptions(categoryId: categoryId, searchPatternWithWildcards: searchPatternWithWildcards, includeFavorites: includeFavorites, orderByFragment: orderByFragment, direction: direction, hasName: true, hasIntroduction: false, hasCourse: hasCourse, hasCategory: hasCategory, hasTag: hasTag, hasIngredients: false)
            }
        } else {
            // No name, but has other fields - use comprehensive handler
            try await loadCategoryRecipesQueryWithAllOptions(categoryId: categoryId, searchPatternWithWildcards: searchPatternWithWildcards, includeFavorites: includeFavorites, orderByFragment: orderByFragment, direction: direction, hasName: false, hasIntroduction: hasIntroduction, hasCourse: hasCourse, hasCategory: hasCategory, hasTag: hasTag, hasIngredients: hasIngredients)
        }
    }
    
    private func loadCategoryRecipesQueryWithAllOptions(categoryId: String, searchPatternWithWildcards: String, includeFavorites: Bool, orderByFragment: String, direction: String, hasName: Bool, hasIntroduction: Bool, hasCourse: Bool, hasCategory: Bool, hasTag: Bool, hasIngredients: Bool) async throws {
        // Handle all combinations explicitly to avoid bind: in empty strings
        // Build a combination identifier
        let combo = (hasName ? 1 : 0) | (hasIntroduction ? 2 : 0) | (hasCourse ? 4 : 0) | (hasCategory ? 8 : 0) | (hasTag ? 16 : 0) | (hasIngredients ? 32 : 0)
        
        // Handle common combinations explicitly
        switch combo {
        case 33: // Name + Ingredients
            try await $recipes.load(
                #sql(
                """
                SELECT DISTINCT \(Recipe.columns) FROM \(Recipe.self)
                INNER JOIN \(RecipeCategory.self) ON \(Recipe.id) = \(RecipeCategory.recipeId)
                WHERE \(RecipeCategory.categoryId) = \(bind: categoryId)
                AND (\(Recipe.name) COLLATE NOCASE LIKE \(bind: searchPatternWithWildcards) OR \(Recipe.ingredients) COLLATE NOCASE LIKE \(bind: searchPatternWithWildcards))
                \(includeFavorites ? "AND \(Recipe.isFavorite) = \(bind: true)" : "")
                ORDER BY \(raw: orderByFragment) \(raw: direction)
                """,
                as: Recipe.self)
            )
        case 3: // Name + Introduction
            try await $recipes.load(
                #sql(
                """
                SELECT DISTINCT \(Recipe.columns) FROM \(Recipe.self)
                INNER JOIN \(RecipeCategory.self) ON \(Recipe.id) = \(RecipeCategory.recipeId)
                WHERE \(RecipeCategory.categoryId) = \(bind: categoryId)
                AND (\(Recipe.name) COLLATE NOCASE LIKE \(bind: searchPatternWithWildcards) OR \(Recipe.introduction) COLLATE NOCASE LIKE \(bind: searchPatternWithWildcards))
                \(includeFavorites ? "AND \(Recipe.isFavorite) = \(bind: true)" : "")
                ORDER BY \(raw: orderByFragment) \(raw: direction)
                """,
                as: Recipe.self)
            )
        case 35: // Name + Introduction + Ingredients
            try await $recipes.load(
                #sql(
                """
                SELECT DISTINCT \(Recipe.columns) FROM \(Recipe.self)
                INNER JOIN \(RecipeCategory.self) ON \(Recipe.id) = \(RecipeCategory.recipeId)
                WHERE \(RecipeCategory.categoryId) = \(bind: categoryId)
                AND (\(Recipe.name) COLLATE NOCASE LIKE \(bind: searchPatternWithWildcards) OR \(Recipe.introduction) COLLATE NOCASE LIKE \(bind: searchPatternWithWildcards) OR \(Recipe.ingredients) COLLATE NOCASE LIKE \(bind: searchPatternWithWildcards))
                \(includeFavorites ? "AND \(Recipe.isFavorite) = \(bind: true)" : "")
                ORDER BY \(raw: orderByFragment) \(raw: direction)
                """,
                as: Recipe.self)
            )
        case 49: // Name + Ingredients + Tag
            try await $recipes.load(
                #sql(
                """
                SELECT DISTINCT \(Recipe.columns) FROM \(Recipe.self)
                INNER JOIN \(RecipeCategory.self) ON \(Recipe.id) = \(RecipeCategory.recipeId)
                WHERE \(RecipeCategory.categoryId) = \(bind: categoryId)
                AND (\(Recipe.name) COLLATE NOCASE LIKE \(bind: searchPatternWithWildcards) OR EXISTS (SELECT 1 FROM \(RecipeTag.self) INNER JOIN \(Tag.self) ON \(RecipeTag.tagId) = \(Tag.id) WHERE \(RecipeTag.recipeId) = \(Recipe.id) AND \(Tag.name) COLLATE NOCASE LIKE \(bind: searchPatternWithWildcards)) OR \(Recipe.ingredients) COLLATE NOCASE LIKE \(bind: searchPatternWithWildcards))
                \(includeFavorites ? "AND \(Recipe.isFavorite) = \(bind: true)" : "")
                ORDER BY \(raw: orderByFragment) \(raw: direction)
                """,
                as: Recipe.self)
            )
        case 51: // Name + Introduction + Ingredients + Tag
            try await $recipes.load(
                #sql(
                """
                SELECT DISTINCT \(Recipe.columns) FROM \(Recipe.self)
                INNER JOIN \(RecipeCategory.self) ON \(Recipe.id) = \(RecipeCategory.recipeId)
                WHERE \(RecipeCategory.categoryId) = \(bind: categoryId)
                AND (\(Recipe.name) COLLATE NOCASE LIKE \(bind: searchPatternWithWildcards) OR \(Recipe.introduction) COLLATE NOCASE LIKE \(bind: searchPatternWithWildcards) OR EXISTS (SELECT 1 FROM \(RecipeTag.self) INNER JOIN \(Tag.self) ON \(RecipeTag.tagId) = \(Tag.id) WHERE \(RecipeTag.recipeId) = \(Recipe.id) AND \(Tag.name) COLLATE NOCASE LIKE \(bind: searchPatternWithWildcards)) OR \(Recipe.ingredients) COLLATE NOCASE LIKE \(bind: searchPatternWithWildcards))
                \(includeFavorites ? "AND \(Recipe.isFavorite) = \(bind: true)" : "")
                ORDER BY \(raw: orderByFragment) \(raw: direction)
                """,
                as: Recipe.self)
            )
        default:
            // For other combinations, route to fallback handler
            try await loadCategoryRecipesQueryWithAllOptionsFallback(categoryId: categoryId, searchPatternWithWildcards: searchPatternWithWildcards, includeFavorites: includeFavorites, orderByFragment: orderByFragment, direction: direction, hasName: hasName, hasIntroduction: hasIntroduction, hasCourse: hasCourse, hasCategory: hasCategory, hasTag: hasTag, hasIngredients: hasIngredients)
        }
    }
    
    private func loadCategoryRecipesQueryWithAllOptionsFallback(categoryId: String, searchPatternWithWildcards: String, includeFavorites: Bool, orderByFragment: String, direction: String, hasName: Bool, hasIntroduction: Bool, hasCourse: Bool, hasCategory: Bool, hasTag: Bool, hasIngredients: Bool) async throws {
        // Handle all remaining combinations explicitly
        // The error shows: Name + Introduction + Tag + Ingredients (combo 51)
        // But combo 51 should already be handled above, so this might be a routing issue
        // Let's handle it explicitly here too, and add more cases
        
        if hasName && hasIntroduction && hasTag && hasIngredients && !hasCourse && !hasCategory {
            // Name + Introduction + Tag + Ingredients (combo 51)
            try await $recipes.load(
                #sql(
                """
                SELECT DISTINCT \(Recipe.columns) FROM \(Recipe.self)
                INNER JOIN \(RecipeCategory.self) ON \(Recipe.id) = \(RecipeCategory.recipeId)
                WHERE \(RecipeCategory.categoryId) = \(bind: categoryId)
                AND (\(Recipe.name) COLLATE NOCASE LIKE \(bind: searchPatternWithWildcards) OR \(Recipe.introduction) COLLATE NOCASE LIKE \(bind: searchPatternWithWildcards) OR EXISTS (SELECT 1 FROM \(RecipeTag.self) INNER JOIN \(Tag.self) ON \(RecipeTag.tagId) = \(Tag.id) WHERE \(RecipeTag.recipeId) = \(Recipe.id) AND \(Tag.name) COLLATE NOCASE LIKE \(bind: searchPatternWithWildcards)) OR \(Recipe.ingredients) COLLATE NOCASE LIKE \(bind: searchPatternWithWildcards))
                \(includeFavorites ? "AND \(Recipe.isFavorite) = \(bind: true)" : "")
                ORDER BY \(raw: orderByFragment) \(raw: direction)
                """,
                as: Recipe.self)
            )
        } else if hasName && hasIntroduction && hasTag && !hasCourse && !hasCategory && !hasIngredients {
            // Name + Introduction + Tag
            try await $recipes.load(
                #sql(
                """
                SELECT DISTINCT \(Recipe.columns) FROM \(Recipe.self)
                INNER JOIN \(RecipeCategory.self) ON \(Recipe.id) = \(RecipeCategory.recipeId)
                WHERE \(RecipeCategory.categoryId) = \(bind: categoryId)
                AND (\(Recipe.name) COLLATE NOCASE LIKE \(bind: searchPatternWithWildcards) OR \(Recipe.introduction) COLLATE NOCASE LIKE \(bind: searchPatternWithWildcards) OR EXISTS (SELECT 1 FROM \(RecipeTag.self) INNER JOIN \(Tag.self) ON \(RecipeTag.tagId) = \(Tag.id) WHERE \(RecipeTag.recipeId) = \(Recipe.id) AND \(Tag.name) COLLATE NOCASE LIKE \(bind: searchPatternWithWildcards)))
                \(includeFavorites ? "AND \(Recipe.isFavorite) = \(bind: true)" : "")
                ORDER BY \(raw: orderByFragment) \(raw: direction)
                """,
                as: Recipe.self)
            )
        } else if hasName && hasTag && !hasIntroduction && !hasCourse && !hasCategory && !hasIngredients {
            // Name + Tag
            try await $recipes.load(
                #sql(
                """
                SELECT DISTINCT \(Recipe.columns) FROM \(Recipe.self)
                INNER JOIN \(RecipeCategory.self) ON \(Recipe.id) = \(RecipeCategory.recipeId)
                WHERE \(RecipeCategory.categoryId) = \(bind: categoryId)
                AND (\(Recipe.name) COLLATE NOCASE LIKE \(bind: searchPatternWithWildcards) OR EXISTS (SELECT 1 FROM \(RecipeTag.self) INNER JOIN \(Tag.self) ON \(RecipeTag.tagId) = \(Tag.id) WHERE \(RecipeTag.recipeId) = \(Recipe.id) AND \(Tag.name) COLLATE NOCASE LIKE \(bind: searchPatternWithWildcards)))
                \(includeFavorites ? "AND \(Recipe.isFavorite) = \(bind: true)" : "")
                ORDER BY \(raw: orderByFragment) \(raw: direction)
                """,
                as: Recipe.self)
            )
        } else {
            // For other complex combinations, default to searching only in name to avoid SQL errors
            // This is a limitation - ideally we'd handle all combinations explicitly
            try await $recipes.load(
                #sql(
                """
                SELECT DISTINCT \(Recipe.columns) FROM \(Recipe.self)
                INNER JOIN \(RecipeCategory.self) ON \(Recipe.id) = \(RecipeCategory.recipeId)
                WHERE \(RecipeCategory.categoryId) = \(bind: categoryId)
                AND \(Recipe.name) COLLATE NOCASE LIKE \(bind: searchPatternWithWildcards)
                \(includeFavorites ? "AND \(Recipe.isFavorite) = \(bind: true)" : "")
                ORDER BY \(raw: orderByFragment) \(raw: direction)
                """,
                as: Recipe.self)
            )
        }
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
        let hasIngredients = searchOptions.contains(.ingredients)
        //let hasNotes = searchOptions.contains(.notes)
        //let hasVariations = searchOptions.contains(.variations)
        // Combining to make easy for now; would like to separate some day:
        let hasNotesOrVariations = searchOptions.contains(.notes)
        let hasCourse = searchOptions.contains(.course)
        let hasCategory = searchOptions.contains(.category)
        let hasTag = searchOptions.contains(.tags)
        let activeCount = [hasName, hasIntroduction, hasCourse, hasCategory, hasTag, hasIngredients, hasNotesOrVariations].filter { $0 }.count
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
                \(hasIntroduction && (hasCourse || hasCategory || hasTag || hasIngredients || hasNotesOrVariations) ? " OR " : "")
                \(hasCourse ? "EXISTS (SELECT 1 FROM \(Course.self) WHERE \(Course.id) = \(Recipe.courseId) AND \(Course.name) COLLATE NOCASE LIKE \(bind: searchPatternWithWildcards))" : "")
                \(hasCourse && (hasCategory || hasTag || hasIngredients || hasNotesOrVariations) ? " OR " : "")
                \(hasCategory ? "EXISTS (SELECT 1 FROM \(RecipeCategory.self) INNER JOIN \(Category.self) ON \(RecipeCategory.categoryId) = \(Category.id) WHERE \(RecipeCategory.recipeId) = \(Recipe.id) AND \(Category.name) COLLATE NOCASE LIKE \(bind: searchPatternWithWildcards))" : "")
                \(hasCategory && (hasTag || hasIngredients || hasNotesOrVariations) ? " OR " : "")
                \(hasTag ? "EXISTS (SELECT 1 FROM \(RecipeTag.self) INNER JOIN \(Tag.self) ON \(RecipeTag.tagId) = \(Tag.id) WHERE \(RecipeTag.recipeId) = \(Recipe.id) AND \(Tag.name) COLLATE NOCASE LIKE \(bind: searchPatternWithWildcards))" : "")
                \(hasTag && (hasIngredients || hasNotesOrVariations) ? " OR " : "")
                \(hasIngredients ? "\(Recipe.ingredients) COLLATE NOCASE LIKE \(bind: searchPatternWithWildcards)" : "")
                \(hasIngredients && hasNotesOrVariations ? " OR " : "")
                \(hasNotesOrVariations ? "(\(Recipe.notes) COLLATE NOCASE LIKE \(bind: searchPatternWithWildcards) OR \(Recipe.variations) COLLATE NOCASE LIKE \(bind: searchPatternWithWildcards))" : "")
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
        let hasTag = searchOptions.contains(.tags)
        let hasIngredients = searchOptions.contains(.ingredients)
        //let hasNotes = searchOptions.contains(.notes)
        //let hasVariations = searchOptions.contains(.variations)
        // Combining to make easy for now; would like to separate some day:
        let hasNotesOrVariations = searchOptions.contains(.notes)
        let activeCount = [hasName, hasIntroduction, hasCourse, hasCategory, hasTag, hasIngredients, hasNotesOrVariations].filter { $0 }.count
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
                \(hasIntroduction && (hasCourse || hasCategory || hasTag || hasIngredients || hasNotesOrVariations) ? " OR " : "")
                \(hasCourse ? "EXISTS (SELECT 1 FROM \(Course.self) WHERE \(Course.id) = \(Recipe.courseId) AND \(Course.name) COLLATE NOCASE LIKE \(bind: searchPatternWithWildcards))" : "")
                \(hasCourse && (hasCategory || hasTag || hasIngredients || hasNotesOrVariations) ? " OR " : "")
                \(hasCategory ? "EXISTS (SELECT 1 FROM \(RecipeCategory.self) INNER JOIN \(Category.self) ON \(RecipeCategory.categoryId) = \(Category.id) WHERE \(RecipeCategory.recipeId) = \(Recipe.id) AND \(Category.name) COLLATE NOCASE LIKE \(bind: searchPatternWithWildcards))" : "")
                \(hasCategory && (hasTag || hasIngredients || hasNotesOrVariations) ? " OR " : "")
                \(hasTag ? "EXISTS (SELECT 1 FROM \(RecipeTag.self) AS rt2 INNER JOIN \(Tag.self) ON rt2.tagId = \(Tag.id) WHERE rt2.recipeId = \(Recipe.id) AND \(Tag.name) COLLATE NOCASE LIKE \(bind: searchPatternWithWildcards))" : "")
                \(hasTag && (hasIngredients || hasNotesOrVariations) ? " OR " : "")
                \(hasIngredients ? "\(Recipe.ingredients) COLLATE NOCASE LIKE \(bind: searchPatternWithWildcards)" : "")
                \(hasIngredients && hasNotesOrVariations ? " OR " : "")
                \(hasNotesOrVariations ? "(\(Recipe.notes) COLLATE NOCASE LIKE \(bind: searchPatternWithWildcards) OR \(Recipe.variations) COLLATE NOCASE LIKE \(bind: searchPatternWithWildcards))" : "")
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
            // For "All Recipes", pass pattern with wildcards (loadAllRecipesQuery handles it differently)
            // For category/course/tag queries, pass plain string (they add wildcards themselves)
            let searchPatternForAll = searchString.isEmpty ? nil : "%\(searchString)%"
            let searchPatternForFilter = searchString.isEmpty ? nil : searchString
            let includeFavorites = isFavoritesFilterActive
            
            if isAllRecipes {
                try await loadAllRecipesQuery(searchPattern: searchPatternForAll, includeFavorites: includeFavorites, sortOrder: recipeListSortOrder, sortDirection: recipeListSortDirection)
            } else if let selectedId = selectedSidebarItemId {
                if selectedId.hasPrefix(categoryPrefix) {
                    let categoryId = String(selectedId.dropFirst(categoryPrefix.count))
                    try await loadCategoryRecipesQuery(categoryId: categoryId, searchPattern: searchPatternForFilter, includeFavorites: includeFavorites, sortOrder: recipeListSortOrder, sortDirection: recipeListSortDirection)
                } else if selectedId.hasPrefix(coursePrefix) {
                    let courseId = String(selectedId.dropFirst(coursePrefix.count))
                    try await loadCourseRecipesQuery(courseId: courseId, searchPattern: searchPatternForFilter, includeFavorites: includeFavorites, sortOrder: recipeListSortOrder, sortDirection: recipeListSortDirection)
                } else if selectedId.hasPrefix(tagPrefix) {
                    let tagId = String(selectedId.dropFirst(tagPrefix.count))
                    try await loadTagRecipesQuery(tagId: tagId, searchPattern: searchPatternForFilter, includeFavorites: includeFavorites, sortOrder: recipeListSortOrder, sortDirection: recipeListSortDirection)
                } else {
                    // Legacy: treat as category ID without prefix (for backward compatibility)
                    try await loadCategoryRecipesQuery(categoryId: selectedId, searchPattern: searchPatternForFilter, includeFavorites: includeFavorites, sortOrder: recipeListSortOrder, sortDirection: recipeListSortDirection)
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
                    exportContentType = .saltyRecipe
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
                    exportContentType = .saltyRecipe
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
    
    /// Shows HTML export settings for a single recipe
    /// - Parameter recipeId: The ID of the recipe to export
    func showHTMLExportSettingsForRecipe(_ recipeId: String) {
        guard recipes.first(where: { $0.id == recipeId }) != nil else {
            exportErrorMessage = "Recipe not found"
            showingExportErrorAlert = true
            return
        }
        
        htmlExportRecipeId = recipeId
        showingHTMLExportSettings = true
        htmlExportOptions = HTMLExportOptions() // Reset to defaults
    }
    
    /// Shows HTML export settings for selected recipes
    func showHTMLExportSettings() {
        let recipesToExport = recipes.filter { selectedRecipeIDs.contains($0.id) }
        
        if recipesToExport.isEmpty {
            exportErrorMessage = "No recipes selected for export"
            showingExportErrorAlert = true
            return
        }
        
        htmlExportRecipeId = nil // Clear single recipe ID when exporting multiple
        showingHTMLExportSettings = true
        htmlExportOptions = HTMLExportOptions() // Reset to defaults
    }
    
    /// Performs the actual HTML export after settings are confirmed
    func performHTMLExport() {
        Task {
            do {
                // Determine which recipes to export
                let recipesToExport: [Recipe]
                if let recipeId = htmlExportRecipeId {
                    // Single recipe export from detail view
                    guard let recipe = recipes.first(where: { $0.id == recipeId }) else {
                        await MainActor.run {
                            exportErrorMessage = "Recipe not found"
                            showingExportErrorAlert = true
                        }
                        return
                    }
                    recipesToExport = [recipe]
                } else {
                    // Multiple recipes from list view
                    recipesToExport = recipes.filter { selectedRecipeIDs.contains($0.id) }
                    
                    if recipesToExport.isEmpty {
                        await MainActor.run {
                            exportErrorMessage = "No recipes selected for export"
                            showingExportErrorAlert = true
                        }
                        return
                    }
                }
                
                if recipesToExport.count == 1 {
                    // Single recipe export
                    let recipe = recipesToExport.first!
                    let htmlString = recipe.asHtmlWithOptions(options: htmlExportOptions)
                    guard let htmlData = htmlString.data(using: .utf8) else {
                        await MainActor.run {
                            exportErrorMessage = "Failed to convert HTML to data"
                            showingExportErrorAlert = true
                        }
                        return
                    }
                    
                    await MainActor.run {
                        exportData = htmlData
                        exportContentType = .html
                        exportFileName = "\(recipe.name).html"
                        showingExportSheet = true
                        // Clear the single recipe ID after export
                        htmlExportRecipeId = nil
                    }
                } else {
                    // Multiple recipes - create a combined HTML document
                    let htmlParts = recipesToExport.map { $0.asHtmlWithOptions(options: htmlExportOptions) }
                    let combinedHTML = """
                    <!DOCTYPE html>
                    <html>
                    <head>
                        <meta charset="UTF-8">
                        <title>Exported Recipes</title>
                    </head>
                    <body>
                        \(htmlParts.joined(separator: "<hr style='margin: 2em 0; border: none; border-top: 2px solid #ccc;'>"))
                    </body>
                    </html>
                    """
                    
                    guard let htmlData = combinedHTML.data(using: .utf8) else {
                        await MainActor.run {
                            exportErrorMessage = "Failed to convert HTML to data"
                            showingExportErrorAlert = true
                        }
                        return
                    }
                    
                    await MainActor.run {
                        exportData = htmlData
                        exportContentType = .html
                        let count = recipesToExport.count
                        exportFileName = count == 1 ? "\(recipesToExport.first!.name).html" : "\(count)_recipes.html"
                        showingExportSheet = true
                    }
                }
            } catch {
                await MainActor.run {
                    exportErrorMessage = "Export failed: \(error.localizedDescription)"
                    showingExportErrorAlert = true
                }
            }
        }
    }
    
    /// Prints the selected recipe(s)
    func printSelectedRecipes() {
        logger.info("printSelectedRecipes called, selectedRecipeIDs: \(self.selectedRecipeIDs)")
        let recipesToPrint = recipes.filter { selectedRecipeIDs.contains($0.id) }
        
        logger.info("Found \(recipesToPrint.count) recipes to print")
        
        if recipesToPrint.isEmpty {
            logger.warning("No recipes selected for printing")
            exportErrorMessage = "No recipes selected for printing"
            showingExportErrorAlert = true
            return
        }
        
        // For now, print only the first selected recipe
        // TODO: Support printing multiple recipes
        let recipe = recipesToPrint.first!
        logger.info("Printing recipe: \(recipe.name)")
        let htmlString = recipe.asHtmlWithOptions(options: htmlExportOptions)
        
        // Print directly using WKWebView without a sheet
        #if os(macOS)
        printRecipeDirectly(htmlContent: htmlString, recipeName: recipe.name)
        #endif
    }
    
    #if os(macOS)
    /// Prints HTML content directly using a temporary WKWebView
    private func printRecipeDirectly(htmlContent: String, recipeName: String) {
        logger.info("Starting print operation")
        
        // Get paper size first
        let printInfo = NSPrintInfo.shared
        let paperSize = printInfo.paperSize
        
        let configuration = WKWebViewConfiguration()
        
        // Create webView with a larger frame to allow full content rendering
        // The webView needs to be able to show all content, not just one page
        let webViewFrame = NSRect(x: 0, y: 0, width: paperSize.width, height: 2000) // Tall enough for multiple pages
        let webView = WKWebView(frame: webViewFrame, configuration: configuration)
        
        // Create a visible preview window
        let windowFrame = NSRect(x: 0, y: 0, width: 800, height: 1000)
        let window = NSWindow(
            contentRect: windowFrame,
            styleMask: [.titled, .closable, .miniaturizable],
            backing: .buffered,
            defer: false
        )
        window.title = "Print Preview"
        window.center()
        
        // Create a scroll view to contain the webView
        let scrollView = NSScrollView(frame: window.contentView!.bounds)
        scrollView.autoresizingMask = [.width, .height]
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autohidesScrollers = true
        scrollView.borderType = .noBorder
        
        webView.frame = webViewFrame
        webView.autoresizingMask = [.width] // Allow width to resize, but height stays at content size
        
        scrollView.documentView = webView
        window.contentView = scrollView
        window.makeKeyAndOrderFront(nil)
        
        // Create a coordinator to handle printing after load
        let coordinator = PrintCoordinator(webView: webView, window: window, logger: logger, recipeName: recipeName)
        webView.navigationDelegate = coordinator
        
        // Store coordinator in window's userInfo to retain it
        objc_setAssociatedObject(window, "printCoordinator", coordinator, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
        
        logger.info("Loading HTML content for printing")
        // Load the HTML content
        webView.loadHTMLString(htmlContent, baseURL: nil)
    }
    
    private class PrintCoordinator: NSObject, WKNavigationDelegate {
        let webView: WKWebView
        let window: NSWindow
        let logger: Logger
        let recipeName: String
        
        init(webView: WKWebView, window: NSWindow, logger: Logger, recipeName: String) {
            self.webView = webView
            self.window = window
            self.logger = logger
            self.recipeName = recipeName
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            logger.info("WebView finished loading, waiting for rendering")
            
            // Ensure the window is visible and on-screen
            window.makeKeyAndOrderFront(nil)
            window.displayIfNeeded()
            
            // Wait for rendering to complete - give it more time to ensure proper layout
            DispatchQueue.main.asyncAfter(deadline: .now() + 1.0) {
                // Force the webView to update its display
                webView.setNeedsDisplay(webView.bounds)
                webView.displayIfNeeded()
                
                // Force the window to update
                self.window.displayIfNeeded()
                
                // Wait for the next run loop to ensure layout is complete
                DispatchQueue.main.async {
                    // Wait a bit more for layout to complete
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        self.printWebView(webView)
                    }
                }
            }
        }
        
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            logger.error("WebView failed to load: \(error.localizedDescription)")
            DispatchQueue.main.async {
                self.window.close()
            }
        }
        
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            logger.error("WebView failed provisional navigation: \(error.localizedDescription)")
            DispatchQueue.main.async {
                self.window.close()
            }
        }
        
        private func printWebView(_ webView: WKWebView) {
            logger.info("Starting print operation")
            
            // Ensure the webView has a valid frame before printing
            guard webView.frame.width > 0 && webView.frame.height > 0 else {
                logger.error("WebView frame is invalid: width=\(webView.frame.width), height=\(webView.frame.height)")
                DispatchQueue.main.async {
                    self.window.close()
                }
                return
            }
            
            logger.info("WebView frame: width=\(webView.frame.width), height=\(webView.frame.height)")
            
            // Ensure window and webView are visible and laid out
            window.makeKeyAndOrderFront(nil)
            window.displayIfNeeded()
            webView.setNeedsDisplay(webView.bounds)
            webView.displayIfNeeded()
            
            // Use JavaScript to ensure the document is fully ready and force a reflow
            // Also wait for images to load if any
            webView.evaluateJavaScript("""
                (function() {
                    // Force a reflow
                    document.body.offsetHeight;
                    var style = window.getComputedStyle(document.body);
                    style.width;
                    
                    // Wait for images to load
                    var images = document.getElementsByTagName('img');
                    var promises = Array.from(images).map(function(img) {
                        if (img.complete) return Promise.resolve();
                        return new Promise(function(resolve, reject) {
                            img.onload = resolve;
                            img.onerror = resolve; // Resolve even on error
                            setTimeout(resolve, 2000); // Timeout after 2 seconds
                        });
                    });
                    
                    return Promise.all(promises).then(function() {
                        return document.readyState;
                    });
                })();
            """) { [weak self] result, error in
                guard let self = self else { return }
                
                if let error = error {
                    self.logger.error("JavaScript evaluation error: \(error.localizedDescription)")
                }
                
                // Force multiple layout passes to ensure everything is ready
                DispatchQueue.main.async {
                    // Ensure window is key and visible
                    self.window.makeKeyAndOrderFront(nil)
                    self.window.displayIfNeeded()
                    
                    // Force the webView to update
                    webView.setNeedsDisplay(webView.bounds)
                    webView.displayIfNeeded()
                    
                    // Run through multiple run loops to ensure layout is complete
                    DispatchQueue.main.async {
                        DispatchQueue.main.async {
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                                self.createPrintOperation(webView: webView, recipeName: self.recipeName)
                            }
                        }
                    }
                }
            }
        }
        
        private func createPrintOperation(webView: WKWebView, recipeName: String) {
            logger.info("Creating print operation")
            
            // Get and configure print info
            let printInfo = NSPrintInfo.shared
            
            // Configure print settings
            printInfo.orientation = .portrait
            printInfo.verticalPagination = .automatic
            printInfo.horizontalPagination = .automatic
            printInfo.isVerticallyCentered = false
            printInfo.isHorizontallyCentered = false
            
            // Ensure paper size matches webView frame
            let paperSize = printInfo.paperSize
            logger.info("Paper size: width=\(paperSize.width), height=\(paperSize.height)")
            logger.info("WebView frame: width=\(webView.frame.width), height=\(webView.frame.height)")
            
            // Verify webView frame matches paper size
            if abs(webView.frame.width - paperSize.width) > 1.0 || abs(webView.frame.height - paperSize.height) > 1.0 {
                logger.warning("WebView frame doesn't match paper size - adjusting")
                webView.frame = NSRect(x: webView.frame.origin.x, y: webView.frame.origin.y, width: paperSize.width, height: paperSize.height)
                webView.setNeedsDisplay(webView.bounds)
                webView.displayIfNeeded()
                
                // Wait for frame adjustment
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    self.performPrint(webView: webView, printInfo: printInfo, recipeName: recipeName)
                }
            } else {
                performPrint(webView: webView, printInfo: printInfo, recipeName: recipeName)
            }
        }
        
        private func performPrint(webView: WKWebView, printInfo: NSPrintInfo, recipeName: String) {
            logger.info("Performing print operation")
            
            // Ensure webView is fully visible and rendered
            window.makeKeyAndOrderFront(nil)
            window.displayIfNeeded()
            
            // Force the webView to render by taking a snapshot
            // This ensures the backing store is fully initialized
            let snapshotConfig = WKSnapshotConfiguration()
            snapshotConfig.rect = webView.bounds
            
            webView.takeSnapshot(with: snapshotConfig) { [weak self] image, error in
                guard let self = self else { return }
                
                if let error = error {
                    self.logger.error("Snapshot error: \(error.localizedDescription)")
                } else {
                    self.logger.info("Snapshot taken successfully, webView is rendered")
                }
                
                // Now create the print operation after we know the webView is rendered
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    self.logger.info("Creating print operation after snapshot")
                    self.printAsPDF(webView: webView, printInfo: printInfo)
                }
            }
        }
        
        /// Generate PDF and save to temporary directory
        private func printAsPDF(webView: WKWebView, printInfo: NSPrintInfo) {
            logger.info("Generating PDF for printing")
            
            let paperSize = printInfo.paperSize
            
            // Get the actual content size from the webView
            webView.evaluateJavaScript("""
                ({
                    width: Math.max(document.body.scrollWidth, document.body.offsetWidth, document.documentElement.clientWidth, document.documentElement.scrollWidth, document.documentElement.offsetWidth),
                    height: Math.max(document.body.scrollHeight, document.body.offsetHeight, document.documentElement.clientHeight, document.documentElement.scrollHeight, document.documentElement.offsetHeight)
                })
            """) { [weak self] contentSize, error in
                guard let self = self else { return }
                
                if let error = error {
                    self.logger.error("Failed to get content size: \(error.localizedDescription)")
                }
                
                var contentWidth = paperSize.width
                var contentHeight: CGFloat = 2000
                
                if let sizeDict = contentSize as? [String: Any],
                   let width = sizeDict["width"] as? CGFloat,
                   let height = sizeDict["height"] as? CGFloat {
                    contentWidth = width
                    contentHeight = height
                    self.logger.info("Content size: width=\(width), height=\(height)")
                }
                
                // Update webView frame to match content size
                DispatchQueue.main.async {
                    // Ensure webView is sized to paper width and full content height
                    let finalHeight = max(contentHeight, 2000)
                    webView.frame = NSRect(x: 0, y: 0, width: paperSize.width, height: finalHeight)
                    webView.setNeedsDisplay(webView.bounds)
                    webView.displayIfNeeded()
                    
                    // Force the scroll view to update
                    if let scrollView = webView.superview as? NSScrollView {
                        scrollView.documentView = webView
                        scrollView.needsLayout = true
                    }
                    
                    // Wait for layout, then generate PDF
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                        // Configure PDF - use webView's full bounds to capture all content
                        let pdfConfig = WKPDFConfiguration()
                        // Set rect to capture the full webView content
                        // Width should be paper width, height should be full content
                        pdfConfig.rect = NSRect(x: 0, y: 0, width: paperSize.width, height: finalHeight)
                        
                        self.logger.info("PDF config rect: width=\(paperSize.width), height=\(finalHeight)")
                        self.logger.info("Paper size: width=\(paperSize.width), height=\(paperSize.height)")
                        self.logger.info("WebView frame: width=\(webView.frame.width), height=\(webView.frame.height)")
                        
                        webView.createPDF(configuration: pdfConfig) { [weak self] result in
                    guard let self = self else { return }
                    
                    switch result {
                    case .success(let pdfData):
                        self.logger.info("PDF generated successfully, size: \(pdfData.count) bytes")
                        
                        // Check how many pages were generated
                        if let pdfDoc = PDFDocument(data: pdfData) {
                            self.logger.info("PDF has \(pdfDoc.pageCount) pages")
                        }
                        
                        DispatchQueue.main.async {
                        // Save PDF to temporary directory
                        let tempDir = FileManager.default.temporaryDirectory
                        // Sanitize filename
                        let sanitizedName = self.recipeName.replacingOccurrences(of: "/", with: "-")
                            .replacingOccurrences(of: ":", with: "-")
                            .replacingOccurrences(of: "\\", with: "-")
                        let fileName = "\(sanitizedName).pdf"
                        let fileURL = tempDir.appendingPathComponent(fileName)
                        
                        do {
                            try pdfData.write(to: fileURL)
                            self.logger.info("PDF saved to: \(fileURL.path)")
                            
                            // Show success message or open the file
                            #if os(macOS)
                            NSWorkspace.shared.open(fileURL)
                            #endif
                            
                            // Close the preview window
                            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                                self.window.close()
                            }
                        } catch {
                            self.logger.error("Failed to save PDF: \(error.localizedDescription)")
                            self.window.close()
                        }
                    }
                    
                    case .failure(let error):
                        self.logger.error("PDF generation failed: \(error.localizedDescription)")
                        DispatchQueue.main.async {
                            self.window.close()
                        }
                    }
                    }
                    }
                }
            }
        }
    }
    #endif
    
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
                    try RecipeCategory.insert { recipeCategory }.execute(db)
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
