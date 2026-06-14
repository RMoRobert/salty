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
import UUIDV7
#if os(macOS)
import WebKit
import AppKit
import ObjectiveC
import QuartzCore
import PDFKit
#else
import UIKit
import WebKit
import ObjectiveC
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
    static let openSelectedRecipesInNewWindows = Notification.Name("openSelectedRecipesInNewWindows")
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
            // Delivered on `.main` (the queue above), so we're already on the main actor;
            // assumeIsolated lets us touch this @MainActor model without a warning or a hop.
            MainActor.assumeIsolated {
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
//                        .where { $0.categoryId.eq(category.id) }
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

    // MARK: - Recipe list query (single dynamic builder)

    /// Reloads `recipes` for the current sidebar scope, search text/fields, favorites filter,
    /// and sort settings. One dynamic SQL builder replaces the previous hand-enumerated
    /// per-combination queries (which silently fell back to name-only for unhandled combos).
    func updateRecipesQuery() async {
        let options = getSelectedSearchOptions()
        let trimmed = searchString.trimmingCharacters(in: .whitespacesAndNewlines)
        let pattern: String? = trimmed.isEmpty ? nil : "%\(trimmed)%"
        do {
            try await $recipes.load(
                RecipeListQueryBuilder.statement(
                    scope: currentScope,
                    searchPattern: pattern,
                    options: options,
                    includeFavorites: isFavoritesFilterActive,
                    sortOrder: recipeListSortOrder,
                    sortDirection: recipeListSortDirection
                )
            )
        } catch {
            logger.error("Error fetching recipes: \(error)")
        }
    }

    /// Maps the selected sidebar item id to a query scope.
    private var currentScope: RecipeListScope {
        guard let selectedId = selectedSidebarItemId, selectedId != allRecipesID else { return .all }
        if selectedId.hasPrefix(categoryPrefix) {
            return .category(String(selectedId.dropFirst(categoryPrefix.count)))
        } else if selectedId.hasPrefix(coursePrefix) {
            return .course(String(selectedId.dropFirst(coursePrefix.count)))
        } else if selectedId.hasPrefix(tagPrefix) {
            return .tag(String(selectedId.dropFirst(tagPrefix.count)))
        } else {
            // Legacy: bare category id without prefix (backward compatibility).
            return .category(selectedId)
        }
    }
    
    // MARK: - Public Methods
    func addNewRecipe() {
        let newRecipe = Recipe(
            id: UUIDV7().uuidString,
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
    
    func deleteSelectedRecipes() async {
        // Snapshot main-actor state for the off-actor @Sendable closures.
        let idsToDelete = selectedRecipeIDs
        do {
            // First, get the image filenames from selected recipes before deleting them
            let imageFilenames = try await database.read { db in
                try Recipe
                    .select { $0.imageFilename }
                    .where { idsToDelete.contains($0.id) }
                    .fetchAll(db)
            }

            // Delete image files from filesystem
            for imageFilename in imageFilenames {
                if let filename = imageFilename {
                    RecipeImageManager.shared.deleteImage(filename: filename)
                }
            }

            // Now delete the recipes from the database
            try await database.write { db in
                try Recipe
                    .where { idsToDelete.contains($0.id) }
                    .delete()
                    .execute(db)
            }

            selectedRecipeIDs.removeAll()
        } catch {
            logger.error("Error deleting recipes: \(error)")
        }
    }

    func deleteRecipe(id: String) async {
        do {
            // First, get the image filename from the recipe before deleting it
            let imageFilenames = try await database.read { db in
                try Recipe
                    .select { $0.imageFilename }
                    .where { $0.id.eq(id) }
                    .fetchAll(db)
            }

            // Delete image file from filesystem if it exists
            for imageFilename in imageFilenames {
                if let filename = imageFilename {
                    RecipeImageManager.shared.deleteImage(filename: filename)
                }
            }

            // Now delete the recipe from the database
            try await database.write { db in
                try Recipe
                    .where { $0.id.eq(id) }
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
                try Recipe.where { $0.id.eq(recipeId) }.fetchOne(db)
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
        printRecipe(by: recipe.id)
    }
    
    /// Prints a recipe by its ID
    func printRecipe(by recipeId: String) {
        logger.info("printRecipe called for recipe ID: \(recipeId)")
        
        guard let recipe = recipes.first(where: { $0.id == recipeId }) else {
            logger.warning("Recipe not found for ID: \(recipeId)")
            exportErrorMessage = "Recipe not found"
            showingExportErrorAlert = true
            return
        }
        
        logger.info("Printing recipe: \(recipe.name)")
        let htmlString = recipe.asHtmlWithOptions(options: htmlExportOptions)
        
        // Print using platform-specific implementation
        #if os(macOS)
        printRecipeDirectly(htmlContent: htmlString, recipeName: recipe.name)
        #else
        printRecipeOniOS(htmlContent: htmlString, recipeName: recipe.name)
        #endif
    }
    
    #if os(macOS)
    /// Prints HTML content using WKWebView - simplified approach based on working example
    private func printRecipeDirectly(htmlContent: String, recipeName: String) {
        logger.info("Starting print operation")
        
        // Get the current window (or main window as fallback)
        let window: NSWindow?
        if let keyWindow = NSApplication.shared.keyWindow {
            window = keyWindow
        } else if let mainWindow = NSApplication.shared.mainWindow {
            window = mainWindow
        } else {
            // Try to get any window
            window = NSApplication.shared.windows.first
        }
        
        guard let targetWindow = window else {
            logger.error("No window available for printing")
            return
        }
        
        // Create and configure the HTML print view
        // Store it in a property to retain it until printing is complete
        let printView = HTMLPrintView()
        printView.printView(htmlContent: htmlContent, window: targetWindow, logger: logger)
        
        // Retain the print view by storing it (it will be released when printing completes)
        // We can use a static storage or associate it with the window
        objc_setAssociatedObject(targetWindow, "htmlPrintView", printView, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
    
    // Simplified HTML print view based on working example - no headers/footers
    private class HTMLPrintView: WKWebView, WKNavigationDelegate {
        private var printOperation: NSPrintOperation?
        private var htmlContent: String?
        private var targetWindow: NSWindow?
        private var logger: Logger?
        
        override init(frame: NSRect, configuration: WKWebViewConfiguration) {
            super.init(frame: frame, configuration: configuration)
        }
        
        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }
        
        convenience init() {
            let configuration = WKWebViewConfiguration()
            let frame = NSRect(x: 0, y: 0, width: 612, height: 792) // US Letter size
            self.init(frame: frame, configuration: configuration)
        }
        
        func printView(htmlContent: String, window: NSWindow, logger: Logger) {
            self.navigationDelegate = self
            self.htmlContent = htmlContent
            self.targetWindow = window
            self.logger = logger
            
            logger.info("HTMLPrintView: Loading HTML content, length: \(htmlContent.count) characters")
            
            // Load the HTML content
            self.loadHTMLString(htmlContent, baseURL: nil)
        }
        
        // MARK: Callback when page loaded
        public func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            logger?.info("HTMLPrintView: didFinish navigation called")
            
            guard self.htmlContent != nil,
                  let targetWindow = self.targetWindow,
                  let logger = self.logger else {
                logger?.error("HTMLPrintView: Missing required properties in didFinish")
                return
            }
            
            DispatchQueue.main.async {
                logger.info("HTMLPrintView: Creating print operation")
                
                // Create a new NSPrintInfo instance (not shared) - this is important for pagination
                let printInfo = NSPrintInfo()
                
                // Configure print info - using .fit for pagination (as in the example)
                printInfo.horizontalPagination = .fit
                printInfo.verticalPagination = .fit
                printInfo.topMargin = 36  // 0.5 inch
                printInfo.bottomMargin = 36
                printInfo.leftMargin = 36
                printInfo.rightMargin = 36
                printInfo.isVerticallyCentered = false
                printInfo.isHorizontallyCentered = false
                printInfo.orientation = .portrait
                
                logger.info("HTMLPrintView: Print info configured, paper size: \(printInfo.paperSize.width)x\(printInfo.paperSize.height)")
                
                // Create print operation from WKWebView
                self.printOperation = self.printOperation(with: printInfo)
                
                guard let pop = self.printOperation else {
                    logger.error("HTMLPrintView: Failed to create print operation")
                    return
                }
                
                logger.info("HTMLPrintView: Print operation created successfully")
                
                // Configure print panel options
                pop.printPanel.options.insert(.showsPaperSize)
                pop.printPanel.options.insert(.showsOrientation)
                pop.printPanel.options.insert(.showsPreview)
                pop.printPanel.options.insert(.showsPageRange)
                pop.printPanel.options.insert(.showsCopies)
                pop.printPanel.options.insert(.showsScaling)
                
                // Set a reasonable frame size for the print view (as in the example)
                pop.view?.frame = NSRect(x: 0.0, y: 0.0, width: 612.0, height: 792.0) // US Letter size
                
                logger.info("HTMLPrintView: About to show print dialog")
                
                // Run the print operation using runModal (as in the example)
                pop.runModal(
                    for: targetWindow,
                    delegate: self,
                    didRun: #selector(self.didRun),
                    contextInfo: nil
                )
                
                logger.info("HTMLPrintView: runModal returned")
            }
        }
        
        // MARK: Error handling
        public func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            logger?.error("HTMLPrintView: Navigation failed: \(error.localizedDescription)")
        }
        
        public func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            logger?.error("HTMLPrintView: Provisional navigation failed: \(error.localizedDescription)")
        }
        
        @objc func didRun() {
            logger?.info("HTMLPrintView: didRun called - print operation completed")
            
            // Release the associated object before clearing targetWindow
            if let window = self.targetWindow {
                objc_setAssociatedObject(window, "htmlPrintView", nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
            }
            
            self.htmlContent = nil
            self.targetWindow = nil
            self.printOperation = nil
        }
    }
    #endif
    
    #if !os(macOS)
    /// Prints HTML content on iOS using UIPrintInteractionController
    func printRecipeOniOS(htmlContent: String, recipeName: String) {
        logger.info("Starting iOS print operation")
        
        // Create a WKWebView to render the HTML
        let configuration = WKWebViewConfiguration()
        let webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 612, height: 792), configuration: configuration)
        
        // Create a coordinator to handle printing after the web view loads
        let coordinator = iOSPrintCoordinator(webView: webView, htmlContent: htmlContent, logger: logger)
        webView.navigationDelegate = coordinator
        
        // Load the HTML content
        webView.loadHTMLString(htmlContent, baseURL: nil)
        
        // Retain the coordinator and webView
        objc_setAssociatedObject(webView, "printCoordinator", coordinator, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
    }
    
    private class iOSPrintCoordinator: NSObject, WKNavigationDelegate {
        let webView: WKWebView
        let htmlContent: String
        let logger: Logger
        
        init(webView: WKWebView, htmlContent: String, logger: Logger) {
            self.webView = webView
            self.htmlContent = htmlContent
            self.logger = logger
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            logger.info("iOSPrintCoordinator: WebView finished loading")
            
            // Wait a moment for rendering to complete
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                self.showPrintDialog()
            }
        }
        
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            logger.error("iOSPrintCoordinator: Navigation failed: \(error.localizedDescription)")
        }
        
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            logger.error("iOSPrintCoordinator: Provisional navigation failed: \(error.localizedDescription)")
        }
        
        private func showPrintDialog() {
            // Create print formatter from web view
            let printFormatter = webView.viewPrintFormatter()
            
            // Configure print info
            let printInfo = UIPrintInfo.printInfo()
            printInfo.outputType = .general
            printInfo.jobName = "Recipe"
            printInfo.orientation = .portrait
            printInfo.duplex = .none
            
            // Create print interaction controller
            let printController = UIPrintInteractionController.shared
            printController.printInfo = printInfo
            printController.printFormatter = printFormatter
            printController.showsNumberOfCopies = true
            printController.showsPaperSelectionForLoadedPapers = true
            
            // Get the current view controller to present from
            if let windowScene = UIApplication.shared.connectedScenes.first as? UIWindowScene,
               let window = windowScene.windows.first,
               let rootViewController = window.rootViewController {
                
                // Find the topmost presented view controller
                var topViewController = rootViewController
                while let presented = topViewController.presentedViewController {
                    topViewController = presented
                }
                
                logger.info("iOSPrintCoordinator: Presenting print dialog")
                
                // Present print dialog
                printController.present(animated: true) { [weak self] printController, completed, error in
                    if let error = error {
                        self?.logger.error("iOSPrintCoordinator: Print error: \(error.localizedDescription)")
                    } else if completed {
                        self?.logger.info("iOSPrintCoordinator: Print completed successfully")
                    } else {
                        self?.logger.info("iOSPrintCoordinator: Print was cancelled")
                    }
                    
                    // Clean up
                    objc_setAssociatedObject(self?.webView as Any, "printCoordinator", nil, .OBJC_ASSOCIATION_RETAIN_NONATOMIC)
                }
            } else {
                logger.error("iOSPrintCoordinator: Could not find view controller to present from")
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
    func addRecipeToCategory(recipeId: String, categoryId: String) async {
        let log = logger // Sendable copy for the off-actor closure
        do {
            try await database.write { db in
                // Check if relationship already exists
                let existingRelationship = try RecipeCategory
                    .where { $0.recipeId.eq(recipeId) && $0.categoryId.eq(categoryId) }
                    .fetchOne(db)

                if existingRelationship == nil {
                    // Create relationship only if it doesn't already exist
                    let recipeCategory = RecipeCategory(
                        id: UUIDV7().uuidString,
                        recipeId: recipeId,
                        categoryId: categoryId
                    )
                    try RecipeCategory.insert { recipeCategory }.execute(db)
                    try Recipe.touchLastModified(recipeId: recipeId, in: db)
                    log.info("Added recipe \(recipeId) to category \(categoryId)")
                } else {
                    log.info("Recipe \(recipeId) is already in category \(categoryId)")
                }
            }
        } catch {
            logger.error("Error adding recipe to category: \(error)")
        }
    }

    /// Adds a recipe to a tag if it's not already associated
    func addRecipeToTag(recipeId: String, tagId: String) async {
        let log = logger // Sendable copy for the off-actor closure
        do {
            try await database.write { db in
                // Check if relationship already exists
                let existingRelationship = try RecipeTag
                    .where { $0.recipeId.eq(recipeId) && $0.tagId.eq(tagId) }
                    .fetchOne(db)

                if existingRelationship == nil {
                    // Create relationship only if it doesn't already exist
                    let recipeTag = RecipeTag(
                        id: UUIDV7().uuidString,
                        recipeId: recipeId,
                        tagId: tagId
                    )
                    try RecipeTag.insert { recipeTag }.execute(db)
                    try Recipe.touchLastModified(recipeId: recipeId, in: db)
                    log.info("Added recipe \(recipeId) to tag \(tagId)")
                } else {
                    log.info("Recipe \(recipeId) is already tagged with \(tagId)")
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
    
    override func deleteSelectedRecipes() async {
        // No-op for preview
    }

    override func deleteRecipe(id: String) async {
        // No-op for preview
    }
}
