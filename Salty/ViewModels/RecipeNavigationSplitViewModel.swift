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
    // Menu-bar commands used to be posted here too; they are now scene-scoped focused values
    // (`MainWindowCommands`), so a command reaches the frontmost main window and no other.
    /// Posted after a web import saves a recipe (userInfo["recipeId"]: String), so the main window/view can scroll to it
    static let recipeImportedFromWeb = Notification.Name("recipeImportedFromWeb")
}

@Observable
@MainActor
class RecipeNavigationSplitViewModel {
    var isNewLaunch = false // true if first launch of app, view should use to show reasonable default instead of blank-looking page on mobile
    
    /// Sort order and search fields, shared with the menu bar and every other main window.
    let settings: RecipeListSettings

    init(isNewLaunch: Bool = false, settings: RecipeListSettings = .shared) {
        self.isNewLaunch = isNewLaunch
        self.settings = settings
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
    
    var recipeListSortOrder: RecipeListSortOrderSetting {
        get { settings.sortOrder }
        set { settings.sortOrder = newValue }
    }

    var recipeListSortDirection: RecipeListSortDirection {
        get { settings.sortDirection }
        set { settings.sortDirection = newValue }
    }

    /// Everything that decides which rows the list shows, for the view's `task(id:)` that reloads it.
    var recipeQueryKey: String {
        "\(searchString)||\(selectedSidebarItem?.queryKey ?? "")||\(isFavoritesFilterActive)||\(settings.queryKey)"
    }

    var showingEditSheet = false
    var recipeToEditID: String?
    /// A recipe just saved or imported that the list should select and scroll to once its row
    /// arrives. The row isn't there yet when this is set: the write has to propagate through
    /// `@FetchAll`, and the list query is usually re-issued at the same time (the scope and search
    /// are reset so the recipe can be seen). `reconcileSelection()` clears it when the row shows up.
    private(set) var pendingRecipeID: String?
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

    // Print options sheet: the recipes waiting on it, and the choices (remembered between prints).
    var showingPrintOptions = false
    var printOptions = RecipePrintOptions.loadFromDefaults()
    private var pendingPrintRecipes: [Recipe] = []
    
    

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
    
    // MARK: - Recipe list query (single dynamic builder)

    /// Reloads `recipes` for the current sidebar scope, search text/fields, favorites filter,
    /// and sort settings. One dynamic SQL builder replaces the previous hand-enumerated
    /// per-combination queries (which silently fell back to name-only for unhandled combos).
    func updateRecipesQuery() async {
        let options = settings.searchOptions
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

    /// Keeps the selection within the rows on screen. Called whenever `recipes` changes: a scope
    /// switch, un-favouriting, a sync delete or a search can all drop a selected row from the list,
    /// and the detail column and the menu commands used to keep acting on it.
    ///
    /// Returns the id of a pending recipe whose row has just arrived, so the view can scroll to it.
    /// Nothing is pruned while that row is still on its way: the selection would be lost before it
    /// could be shown.
    @discardableResult
    func reconcileSelection() -> String? {
        let visibleIDs = Set(recipes.map(\.id))
        if let pending = pendingRecipeID {
            guard visibleIDs.contains(pending) else { return nil }
            pendingRecipeID = nil
            selectedRecipeIDs.formIntersection(visibleIDs)
            return pending
        }
        if !selectedRecipeIDs.isSubset(of: visibleIDs) {
            selectedRecipeIDs.formIntersection(visibleIDs)
        }
        return nil
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
    
    func deleteRecipe(id: String) async {
        await deleteRecipes(ids: [id])
    }

    /// Deletes recipes in one transaction -- a swipe across several rows used to run one per row --
    /// and drops them from the selection, so a deleted recipe can't stay selected.
    func deleteRecipes(ids idsToDelete: Set<String>) async {
        guard !idsToDelete.isEmpty else { return }
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

            selectedRecipeIDs.subtract(idsToDelete)
        } catch {
            logger.error("Error deleting \(idsToDelete.count) recipe(s): \(error)")
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

        // Select the newly saved recipe; the list scrolls to it once its row arrives.
        selectedRecipeIDs = [recipeId]
        pendingRecipeID = recipeId

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
            let ids = try await RecipeFileImportHelper.importIntoDatabase(database, fileUrl: url)
            if let firstId = ids.first {
                handleNewRecipeSaved(recipeId: firstId)
            }
        } catch {
            logger.error("Failed to import opened recipe file: \(error.localizedDescription)")
        }
    }
    
    // MARK: - Export

    /// Builds export files; the app supplies the photos, which live in its own folder.
    nonisolated private static let exporter = RecipeExporter(
        imageData: { $0.fullImageData },
        htmlImageBase64: { $0.imageAsBase64 }
    )

    /// The selected recipes in the order the list shows them.
    private var selectedRecipesInListOrder: [Recipe] {
        fullRecipes(ids: recipes.filter { selectedRecipeIDs.contains($0.id) }.map(\.id))
    }

    /// Exports one recipe as a `.saltyRecipe` file.
    func exportRecipe(_ recipeId: String) {
        presentExport(of: fullRecipe(id: recipeId).map { [$0] } ?? [], as: .saltyFile, whenEmpty: "Recipe not found")
    }

    /// Exports the selected recipes as one `.saltyRecipe` file.
    func exportSelectedRecipes() {
        presentExport(of: selectedRecipesInListOrder, as: .saltyFile, whenEmpty: "No recipes selected for export")
    }

    /// Exports one recipe as schema.org/Recipe JSON-LD.
    func exportRecipeAsJSONLD(_ recipeId: String) {
        presentExport(of: fullRecipe(id: recipeId).map { [$0] } ?? [], as: .jsonLD, whenEmpty: "Recipe not found")
    }

    /// Exports the selected recipes as schema.org/Recipe JSON-LD (one object, or an array if several).
    func exportSelectedRecipesAsJSONLD() {
        presentExport(of: selectedRecipesInListOrder, as: .jsonLD, whenEmpty: "No recipes selected for export")
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
    
    /// Exports HTML once its settings sheet is confirmed: the one recipe it was opened for, or else the
    /// selection.
    func performHTMLExport() {
        let format = RecipeExportFormat.html(htmlExportOptions)
        if let recipeId = htmlExportRecipeId {
            htmlExportRecipeId = nil
            presentExport(of: fullRecipe(id: recipeId).map { [$0] } ?? [], as: format, whenEmpty: "Recipe not found")
        } else {
            presentExport(of: selectedRecipesInListOrder, as: format, whenEmpty: "No recipes selected for export")
        }
    }

    /// Builds the file off the main actor (encoding photos for many recipes takes a moment), then shows
    /// the save panel, or an alert saying why there is nothing to save.
    private func presentExport(of recipesToExport: [Recipe], as format: RecipeExportFormat, whenEmpty emptyMessage: String) {
        guard !recipesToExport.isEmpty else {
            exportErrorMessage = emptyMessage
            showingExportErrorAlert = true
            return
        }
        let database = database
        Task {
            do {
                let file = try await Task.detached(priority: .userInitiated) {
                    try Self.exporter.export(recipesToExport, as: format, database: database)
                }.value
                exportData = file.data
                exportFileName = file.fileName
                exportContentType = Self.contentType(for: file.format)
                showingExportSheet = true
            } catch {
                exportErrorMessage = "Export failed: \(error.localizedDescription)"
                showingExportErrorAlert = true
            }
        }
    }

    private static func contentType(for format: RecipeExportFormat) -> UTType {
        switch format {
        case .saltyFile: .saltyRecipe
        case .jsonLD: .json
        case .html: .html
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

    /// Shows the print options sheet for `recipesToPrint`; `performPrint()` runs when it's confirmed.
    private func printRecipes(_ recipesToPrint: [Recipe]) {
        pendingPrintRecipes = recipesToPrint
        showingPrintOptions = true
    }

    var pendingPrintRecipeCount: Int { pendingPrintRecipes.count }

    /// Prints the recipes the options sheet was shown for, with its current choices.
    func performPrint() {
        let recipesToPrint = pendingPrintRecipes
        pendingPrintRecipes = []
        guard !recipesToPrint.isEmpty else { return }
        printOptions.saveToDefaults()
        let options = printOptions
        // Print with the user's selected recipe theme (matches the web detail view).
        let theme = RecipeHtmlTheme(rawValue: UserDefaults.standard.string(forKey: "recipeHtmlTheme") ?? "") ?? .modern
        let title = recipesToPrint.count == 1 ? recipesToPrint[0].name : "\(recipesToPrint.count) Recipes"
        let jobs = recipesToPrint.map { recipe -> RecipePrintJob in
            let page = recipe.htmlPage(database: database, grayscaleImage: options.colorMode == .grayscale)   // names + photo, once
            let footer = [recipe.source, recipe.sourceDetails].filter { !$0.isEmpty }.joined(separator: " — ")
            return RecipePrintJob(headerText: recipe.name, footerText: footer) { scale in
                RecipeHtmlDocument.render([page], options: options.content, theme: theme, title: recipe.name,
                                          printOptions: options, printScale: scale)
            }
        }
        logger.info("Printing: \(title) (\(options.paperSize.rawValue) \(options.orientation.rawValue))")
        RecipePrinter.print(jobs: jobs, options: options, jobTitle: title)
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
                try await RecipeFileImportHelper.importIntoDatabase(database, fileUrl: demoImportUrl)
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
            contentsForFreeform: isFreeform ? "" : nil
            // `lastModifiedDate` is stamped by `ShoppingListWriter.insert` below.
        )
        do {
            let created = try await database.write { db in
                try ShoppingListWriter.insert(newList, in: db)
            }
            selectedSidebarItem = .allShoppingLists
            selectedShoppingListIDs = [created.id]
            return created
        } catch {
            logger.error("Error creating shopping list: \(error)")
            return nil
        }
    }

    func renameShoppingList(id: String, to name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        do {
            _ = try await database.write { db in
                try ShoppingListWriter.update(id: id, in: db) { list in
                    list.name = trimmed
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
    
    override func deleteRecipes(ids: Set<String>) async {
        // No-op for preview
    }
}
