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
import SaltyCore
#if os(macOS)
import AppKit
#else
import UIKit
#endif

// MARK: - Notification Names

extension Notification.Name {
    static let createNewRecipe = Notification.Name("createNewRecipe")
    static let exportSelectedRecipes = Notification.Name("exportSelectedRecipes")
    static let showImportFromFileSheet = Notification.Name("showImportFromFileSheet")
    static let showCreateFromWebSheet = Notification.Name("showCreateFromWebSheet")
    static let sheetStateChanged = Notification.Name("sheetStateChanged")
    static let showRecipeInfoInspector = Notification.Name("showRecipeInfoInspector")
    static let recipeSelectionChanged = Notification.Name("recipeSelectionChanged")
    static let exportSelectedRecipesAsHTML = Notification.Name("exportSelectedRecipesAsHTML")
    static let exportSelectedRecipesAsJSONLD = Notification.Name("exportSelectedRecipesAsJSONLD")
    static let printSelectedRecipes = Notification.Name("printSelectedRecipes")
    static let openSelectedRecipesInNewWindows = Notification.Name("openSelectedRecipesInNewWindows")
    static let showDuplicateRecipes = Notification.Name("showDuplicateRecipes")
    static let showConsolidateDuplicates = Notification.Name("showConsolidateDuplicates")
    // "Last Made" actions on the current selection. These mirror the recipe context menu — the menu bar
    // carries them too because a contextual menu shouldn't be the only way to reach a command.
    static let markSelectedRecipesMadeToday = Notification.Name("markSelectedRecipesMadeToday")
    static let setSelectedRecipesLastMadeDate = Notification.Name("setSelectedRecipesLastMadeDate")
    static let clearSelectedRecipesLastMade = Notification.Name("clearSelectedRecipesLastMade")
    /// Posted after a web import saves a recipe (userInfo["recipeId"]: String), so the main window/view can scroll to it
    static let recipeImportedFromWeb = Notification.Name("recipeImportedFromWeb")
}

@Observable
@MainActor
class RecipeNavigationSplitViewModel {
    var isNewLaunch = false // true if first launch of app, view should use to show reasonable default instead of blank-looking page on mobile
    
    init(isNewLaunch: Bool = false) {
        self.isNewLaunch = isNewLaunch

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
        if selectedSidebarItem == nil {
            selectedSidebarItem = .allRecipes
        }
    }
    // MARK: - Constants
    private let logger = Logger(subsystem: "Salty", category: "Database")
    
    // MARK: - Dependencies
    @ObservationIgnored
    @Dependency(\.defaultDatabase)
    private var database
    
    // MARK: - Data (using SQLiteData property wrappers)
    // The list holds a lightweight projection (see RecipeListItem); full rows are fetched on demand via
    // fullRecipe(id:). An explicit initial statement is supplied so the query is valid before the view's
    // .task calls updateRecipesQuery() (a no-arg @FetchAll would default to a non-existent table).
    @ObservationIgnored
    @FetchAll(
        RecipeListQueryBuilder.statement(
            scope: .all, searchPattern: nil, options: [],
            includeFavorites: false, includeWantToMake: false,
            sortOrder: .byName, sortDirection: .ascending
        )
    )
    var recipes: [RecipeListItem]
    
    @ObservationIgnored
    @FetchAll(#sql("SELECT \(Category.columns) FROM \(Category.self) ORDER BY \(Category.name) COLLATE NOCASE"))
    var categories: [Category]
    
    @ObservationIgnored
    @FetchAll(#sql("SELECT \(Course.columns) FROM \(Course.self) ORDER BY \(Course.name) COLLATE NOCASE"))
    var courses: [Course]
    
    @ObservationIgnored
    @FetchAll(#sql("SELECT \(Tag.columns) FROM \(Tag.self) ORDER BY \(Tag.name) COLLATE NOCASE"))
    var tags: [Tag]

    @ObservationIgnored
    @FetchAll(#sql("SELECT \(ShoppingList.columns) FROM \(ShoppingList.self) ORDER BY \(ShoppingList.name) COLLATE NOCASE"))
    var shoppingLists: [ShoppingList]
            
    // MARK: - State
    var searchString = ""
    var selectedSidebarItem: SidebarItem?
    var selectedRecipeIDs = Set<String>()
    /// Selection within the shopping-lists content column. Multi-select (like the recipe list) so
    /// several lists can be deleted at once; the detail column only renders when exactly one is
    /// selected, since a multi-selection has no single list to show.
    var selectedShoppingListIDs = Set<String>()
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
    
    

    // Sidebar scope, search, favorites, and sort are all applied in SQL via `updateRecipesQuery()`
    // (see RecipeListQueryBuilder) — no in-memory filtering remains.
    //
    // Remaining optimization: the list still loads full Recipe rows, decoding the
    // ingredients/directions/notes/variations/preparationTimes/nutrition JSON blobs the rows never
    // display. Fetching a lightweight projection instead (id/name/summary/rating/favorite/thumbnail)
    // would cut that — see the RecipeSummary stub in Schema.swift.

    var navigationTitle: String {
        switch selectedSidebarItem {
        case .none, .allRecipes:
            return "Recipes"
        case .favorites:
            return "Favorites"
        case .wantToMake:
            return "Want to Make"
        case .category(let id):
            return categories.first(where: { $0.id == id })?.name ?? "Recipes"
        case .course(let id):
            return courses.first(where: { $0.id == id })?.name ?? "Recipes"
        case .tag(let id):
            return tags.first(where: { $0.id == id })?.name ?? "Recipes"
        case .allShoppingLists:
            return "Shopping Lists"
        }
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
        // The "Favorites" smart list forces the favorites filter; the toolbar toggle composes with any
        // scope (e.g. favorites within a category), so either source turns it on.
        let includeFavorites = isFavoritesFilterActive || (selectedSidebarItem?.forcesFavorites ?? false)
        let includeWantToMake = selectedSidebarItem?.forcesWantToMake ?? false
        do {
            try await $recipes.load(
                RecipeListQueryBuilder.statement(
                    scope: currentScope,
                    searchPattern: pattern,
                    options: options,
                    includeFavorites: includeFavorites,
                    includeWantToMake: includeWantToMake,
                    sortOrder: recipeListSortOrder,
                    sortDirection: recipeListSortDirection
                )
            )
        } catch {
            logger.error("Error fetching recipes: \(error)")
        }
    }

    /// Maps the selected sidebar item to a query scope (nil selection == all recipes).
    private var currentScope: RecipeListScope {
        selectedSidebarItem?.scope ?? .all
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
            // Note the image filenames first; the files go only after the rows are gone.
            let imageFilenames = try await database.read { db in
                try Recipe
                    .select { $0.imageFilename }
                    .where { $0.id.in(idsToDelete) }
                    .fetchAll(db)
            }

            // Delete the recipes from the database, recording a tombstone for each in the SAME
            // transaction so a peer sharing this library can tell "deleted here" from "not yet
            // downloaded". See RecipeTombstoneWriter.
            try await database.write { db in
                try Recipe
                    .where { $0.id.in(idsToDelete) }
                    .delete()
                    .execute(db)
                try RecipeTombstoneWriter.recordDeletions(Array(idsToDelete), in: db)
            }

            // Rows are gone, so nothing references these files any more. Done last: if the write above
            // had failed, the recipes would still exist and must still have their photos.
            for case let filename? in imageFilenames {
                RecipeImageManager.shared.deleteImage(filename: filename)
            }

            selectedRecipeIDs.removeAll()
        } catch {
            logger.error("Error deleting recipes: \(error)")
        }
    }

    func deleteRecipe(id: String) async {
        do {
            // Note the image filename first; the file goes only after the row is gone.
            let imageFilenames = try await database.read { db in
                try Recipe
                    .select { $0.imageFilename }
                    .where { $0.id.eq(id) }
                    .fetchAll(db)
            }

            // Delete the recipe from the database, with its tombstone. See the bulk path above.
            try await database.write { db in
                try Recipe
                    .where { $0.id.eq(id) }
                    .delete()
                    .execute(db)
                try RecipeTombstoneWriter.recordDeletion(id, in: db)
            }

            // Row is gone; now the file. Same ordering rule as the bulk path.
            for case let filename? in imageFilenames {
                RecipeImageManager.shared.deleteImage(filename: filename)
            }
        } catch {
            logger.error("Error deleting recipe \(id): \(error)")
        }
    }
    
    /// Sets (or clears, with `date: nil`) the "last made on" date for one or more recipes.
    ///
    /// A picked calendar day is stored at local noon; "Today" sets current time. Usually only displayed as date, but noon should
    /// at least cover any reasonable offsets to avoid unexpected date changes with minor time zone shifts.
    ///
    /// The write itself lives in `RecipeLastPreparedWriter`, shared with Chef View's "Made It!".
    func setLastMade(_ date: Date?, forRecipeIds ids: [String]) async {
        do {
            try await RecipeLastPreparedWriter.setLastMade(date, forRecipeIds: ids, in: database)
        } catch {
            logger.error("Error setting last-made date for \(ids.count) recipe(s): \(error)")
        }
    }

    /// Local noon on the calendar day of [day] — the storage form for a user-picked date.
    static func localNoon(on day: Date) -> Date {
        RecipeLastPreparedWriter.localNoon(on: day)
    }

    /// Heading for the "Last Prepared Date" menus: the current value for [ids]. Read from the
    /// already-loaded list projection rather than the database, so opening a menu costs nothing.
    func lastPreparedSummary(forRecipeIds ids: [String]) -> String {
        let wanted = Set(ids)
        return LastPreparedSummary.text(for: recipes.filter { wanted.contains($0.id) }.map(\.lastPrepared))
    }

    /// The same heading for whatever is currently selected — what the menu bar's copy shows.
    var lastPreparedSummaryForSelection: String {
        lastPreparedSummary(forRecipeIds: Array(selectedRecipeIDs))
    }

    func recipeToEdit(recipeId: String?) -> Recipe? {
        guard let recipeId = recipeId else { return nil }

        return fullRecipe(id: recipeId)
    }

    /// Resolves the full `Recipe` for an id. The list now holds lightweight `RecipeListItem` projections,
    /// so every caller that needs full recipe data (detail view, edit, export, print, share) goes through
    /// here: the in-progress draft first, then a single-row read from the database.
    func fullRecipe(id recipeId: String) -> Recipe? {
        if let draftRecipe, draftRecipe.id == recipeId {
            return draftRecipe
        }
        do {
            return try database.read { db in
                try Recipe.where { $0.id.eq(recipeId) }.fetchOne(db)
            }
        } catch {
            logger.error("Error fetching full recipe \(recipeId): \(error)")
            return nil
        }
    }

    /// Resolves full `Recipe`s for the given ids (preserving order), skipping any that can't be found.
    /// Used by multi-selection export/print.
    func fullRecipes(ids: [String]) -> [Recipe] {
        ids.compactMap { fullRecipe(id: $0) }
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
        selectedSidebarItem = .allRecipes

        // Clear the search text and favorites filter too: together with the scope above, these are
        // what can otherwise hide the new recipe, leaving it selected but absent from the list.
        searchString = ""
        isFavoritesFilterActive = false

        // Select the newly saved recipe and scroll to it
        selectedRecipeIDs = [recipeId]
        shouldScrollToNewRecipe = true

        // Clear the draft since it's now persisted
        draftRecipe = nil
    }

    /// Imports a confirmed, opened/AirDropped .saltyRecipe file, then selects and scrolls to the first
    /// imported recipe (reusing the new-recipe-saved path).
    func importOpenedRecipeFile(_ url: URL) async {
        // Files handed over from outside the sandbox need security-scoped access while we read them.
        let scoped = url.startAccessingSecurityScopedResource()
        defer { if scoped { url.stopAccessingSecurityScopedResource() } }
        do {
            let ids = try await SaltyRecipeImportHelper.importIntoDatabase(database, jsonFileUrl: url)
            if let firstId = ids.first {
                handleNewRecipeSaved(recipeId: firstId)
            }
        } catch {
            logger.error("Failed to import opened recipe file: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Export Methods
    
    /// Exports a single recipe to JSON format
    /// - Parameter recipeId: The ID of the recipe to export
    func exportRecipe(_ recipeId: String) {
        Task {
            do {
                guard let recipe = fullRecipe(id: recipeId) else {
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
                // Preserve the displayed order via the projection's ids, then fetch full rows.
                let orderedIds = recipes.filter { selectedRecipeIDs.contains($0.id) }.map(\.id)
                let recipesToExport = fullRecipes(ids: orderedIds)

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
    
    // MARK: - Schema.org JSON-LD export

    /// Exports a single recipe as schema.org/Recipe JSON-LD.
    func exportRecipeAsJSONLD(_ recipeId: String) {
        Task {
            do {
                guard let recipe = fullRecipe(id: recipeId) else {
                    await MainActor.run {
                        exportErrorMessage = "Recipe not found"
                        showingExportErrorAlert = true
                    }
                    return
                }
                let data = try SchemaOrgRecipeJSONLDExporter().data(for: recipe, metadata: jsonLDMetadata(for: recipe))
                await MainActor.run {
                    exportData = data
                    exportContentType = .json
                    exportFileName = "\(recipe.name).json"
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

    /// Exports the selected recipes as schema.org/Recipe JSON-LD (one object, or an array if several).
    func exportSelectedRecipesAsJSONLD() {
        Task {
            do {
                let orderedIds = recipes.filter { selectedRecipeIDs.contains($0.id) }.map(\.id)
                let recipesToExport = fullRecipes(ids: orderedIds)

                guard !recipesToExport.isEmpty else {
                    await MainActor.run {
                        exportErrorMessage = "No recipes selected for export"
                        showingExportErrorAlert = true
                    }
                    return
                }

                let items = recipesToExport.map { (recipe: $0, metadata: jsonLDMetadata(for: $0)) }
                let data = try SchemaOrgRecipeJSONLDExporter().data(for: items)
                await MainActor.run {
                    exportData = data
                    exportContentType = .json
                    let count = recipesToExport.count
                    exportFileName = count == 1 ? "\(recipesToExport.first!.name).json" : "\(count)_recipes.json"
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

    /// Resolves the course / category / tag names for a recipe (best-effort — returns empty metadata on
    /// error so the export still proceeds without them).
    private func jsonLDMetadata(for recipe: Recipe) -> SchemaOrgRecipeJSONLDExporter.LibraryMetadata {
        let names = recipe.libraryNames(database: database)
        return .init(courseName: names.course, categoryNames: names.categories, tagNames: names.tags)
    }

    /// Shows HTML export settings for a single recipe
    /// - Parameter recipeId: The ID of the recipe to export
    func showHTMLExportSettingsForRecipe(_ recipeId: String) {
        guard recipes.contains(where: { $0.id == recipeId }) else {
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
        if selectedRecipeIDs.isEmpty {
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
                    guard let recipe = fullRecipe(id: recipeId) else {
                        await MainActor.run {
                            exportErrorMessage = "Recipe not found"
                            showingExportErrorAlert = true
                        }
                        return
                    }
                    recipesToExport = [recipe]
                } else {
                    // Multiple recipes from list view (preserve displayed order via projection ids)
                    let orderedIds = recipes.filter { selectedRecipeIDs.contains($0.id) }.map(\.id)
                    recipesToExport = fullRecipes(ids: orderedIds)

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
                    let names = recipe.libraryNames(database: database)
                    let htmlString = recipe.asHtmlWithOptions(options: htmlExportOptions, course: names.course, categories: names.categories, tags: names.tags)
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
                    // Multiple recipes: one document, one stylesheet, one <main> per recipe.
                    let combinedHTML = RecipeHtmlDocument.render(recipesToExport.map { $0.htmlPage(database: database) },
                                                                 options: htmlExportOptions,
                                                                 title: "\(recipesToExport.count) Recipes")
                    
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
    
    /// Prints every selected recipe as one job, in list order, each starting on its own page.
    func printSelectedRecipes() {
        let orderedIds = recipes.filter { selectedRecipeIDs.contains($0.id) }.map(\.id)
        let recipesToPrint = fullRecipes(ids: orderedIds)
        logger.info("printSelectedRecipes: \(recipesToPrint.count) recipe(s)")
        guard !recipesToPrint.isEmpty else {
            exportErrorMessage = "No recipes selected for printing"
            showingExportErrorAlert = true
            return
        }
        printRecipes(recipesToPrint)
    }

    /// Prints a recipe by its ID
    func printRecipe(by recipeId: String) {
        guard let recipe = fullRecipe(id: recipeId) else {
            logger.warning("Recipe not found for ID: \(recipeId)")
            exportErrorMessage = "Recipe not found"
            showingExportErrorAlert = true
            return
        }
        printRecipes([recipe])
    }

    private func printRecipes(_ recipesToPrint: [Recipe]) {
        // Print with the user's selected recipe theme (matches the web detail view), and with everything
        // included — the HTML export sheet's options are for exports, not printouts.
        let theme = RecipeHtmlTheme(rawValue: UserDefaults.standard.string(forKey: "recipeHtmlTheme") ?? "") ?? .modern
        let title = recipesToPrint.count == 1 ? recipesToPrint[0].name : "\(recipesToPrint.count) Recipes"
        let html = RecipeHtmlDocument.render(recipesToPrint.map { $0.htmlPage(database: database) },
                                             options: HTMLExportOptions(), theme: theme, title: title)
        logger.info("Printing: \(title)")
        RecipePrinter.print(html: html, jobTitle: title)
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
    func addRecipeToCategory(recipeId: String, categoryId: String) async {
        let log = logger // Sendable copy for the off-actor closure
        do {
            try await database.write { db in
                let recipeCategory = RecipeCategory(
                    id: UUIDV7().uuidString,
                    recipeId: recipeId,
                    categoryId: categoryId
                )
                if try RecipeCategory.insertIfAbsent(recipeCategory, in: db) {
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

    // MARK: - Shopping List Management

    /// Creates a new shopping list of the requested kind (checklist or freeform, fixed at creation),
    /// selects it, and returns it. The name is collected before this is called, so cancelling the
    /// name prompt never leaves a list (or a sync record) behind.
    @discardableResult
    func createShoppingList(isFreeform: Bool, name: String = "New List") async -> ShoppingList? {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let newList = ShoppingList(
            id: UUIDV7().uuidString,
            name: trimmed.isEmpty ? "New List" : trimmed,
            isFreeform: isFreeform,
            contentsForFreeform: isFreeform ? "" : nil,
            lastModifiedDate: Date()
        )
        do {
            try await database.write { db in
                try ShoppingList.insert { newList }.execute(db)
            }
            selectedSidebarItem = .allShoppingLists
            selectedShoppingListIDs = [newList.id]
            return newList
        } catch {
            logger.error("Error creating shopping list: \(error)")
            return nil
        }
    }

    func renameShoppingList(id: String, to name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            try await database.write { db in
                if var list = try ShoppingList.where({ $0.id.eq(id) }).fetchOne(db) {
                    list.name = trimmed
                    list.lastModifiedDate = Date()
                    try ShoppingList.update(list).execute(db)
                }
            }
        } catch {
            logger.error("Error renaming shopping list \(id): \(error)")
        }
    }

    func deleteShoppingList(id: String) async {
        await deleteShoppingLists(ids: [id])
    }

    /// Deletes the given lists in one write and drops them from the selection.
    func deleteShoppingLists(ids: Set<String>) async {
        guard !ids.isEmpty else { return }
        do {
            try await database.write { db in
                try ShoppingList.where { $0.id.in(ids) }.delete().execute(db)
            }
            selectedShoppingListIDs.subtract(ids)
        } catch {
            logger.error("Error deleting shopping lists: \(error)")
        }
    }

    /// Deletes everything currently selected in the shopping-lists column.
    func deleteSelectedShoppingLists() async {
        await deleteShoppingLists(ids: selectedShoppingListIDs)
    }

    /// Adds a recipe to a tag if it's not already associated
    func addRecipeToTag(recipeId: String, tagId: String) async {
        let log = logger // Sendable copy for the off-actor closure
        do {
            try await database.write { db in
                let recipeTag = RecipeTag(
                    id: UUIDV7().uuidString,
                    recipeId: recipeId,
                    tagId: tagId
                )
                if try RecipeTag.insertIfAbsent(recipeTag, in: db) {
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
    override var recipes: [RecipeListItem] { previewRecipes.map { RecipeListItem(recipe: $0) } }
    override var categories: [Category] { previewCategories }
    override var courses: [Course] { previewCourses }
    override var tags: [Tag] { previewTags }
    override var shoppingLists: [ShoppingList] { SampleData.sampleShoppingLists }
    
    // MARK: - Initialization
    init(previewData: (recipes: [Recipe], categories: [Category], courses: [Course], tags: [Tag])) {
        self.previewRecipes = previewData.recipes
        self.previewCategories = previewData.categories
        self.previewCourses = previewData.courses
        self.previewTags = previewData.tags
        super.init()
    }
    
    // MARK: - Override database-dependent methods

    /// Resolve full recipes from in-memory preview data instead of the database.
    override func fullRecipe(id recipeId: String) -> Recipe? {
        previewRecipes.first { $0.id == recipeId }
    }

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
