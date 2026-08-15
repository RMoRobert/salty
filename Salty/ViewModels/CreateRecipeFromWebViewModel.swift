//
//  CreateRecipeFromWebViewModel.swift
//  Salty
//  Created by Robert on 7/13/25
//

import Foundation
import OSLog
import SQLiteData
import UUIDV7
import SaltyCore

@Observable
@MainActor
class CreateRecipeFromWebViewModel {
    // MARK: - Constants
    private let logger = Logger(subsystem: "Salty", category: "CreateRecipeFromWeb")
    
    // MARK: - Dependencies
    @ObservationIgnored
    @Dependency(\.defaultDatabase) private var database
    
    // MARK: - Data
    @ObservationIgnored
    @FetchAll(#sql("SELECT \(Course.columns) FROM \(Course.self) ORDER BY \(Course.name) COLLATE NOCASE"))
    var courses: [Course]
    
    // MARK: - Recipe State
    var recipe: Recipe

    /// True once the recipe has been saved — by this view model (macOS) or by the hand-off
    /// editor (iOS). Checked on dismissal so a discarded import can clean up its photo.
    var recipeWasSaved = false

    /// Set when the import UI is dismissed. A photo download still in flight at that point
    /// is discarded instead of attached, so it can't recreate the file cleanup just removed.
    private var importSessionEnded = false
    
    // MARK: - Plain Text State for Import
    var ingredientsText: String = ""
    var directionsText: String = ""
    
    // MARK: - Category State
    var selectedCategoryIDs: Set<String> = []
    
    // MARK: - Web Browser State
    var currentURL: String = ""
    var canGoBack = false
    var canGoForward = false
    var isLoading = false
    
    // MARK: - UI State
    var showingCategoriesSheet = false
    var showingPreparationTimesSheet = false
    var showingImageEditSheet = false
    var showingNotesSheet = false
    var showingNutritionEditSheet = false
    var showingSaveAlert = false
    var showingCancelAlert = false
    var showingExtractedDataSheet = false
    var showingNoRecipeDataAlert = false
    var showingSaveErrorAlert = false
    var saveErrorMessage: String?
    
    // MARK: - Computed Properties
    var hasRecipeData: Bool {
        let hasBasicInfo = !recipe.name.isEmpty || 
                          !recipe.source.isEmpty || 
                          !recipe.sourceDetails.isEmpty || 
                          !recipe.introduction.isEmpty
        
        let hasStructuredContent = !recipe.ingredients.isEmpty ||
                                  !recipe.directions.isEmpty ||
                                  !recipe.notes.isEmpty
        
        let hasTextContent = !ingredientsText.isEmpty ||
                            !directionsText.isEmpty
        
        return hasBasicInfo || hasStructuredContent || hasTextContent
    }
    
    // MARK: - Initialization
    init() {
        self.recipe = Recipe(
            id: UUIDV7().uuidString,
            name: "",
            createdDate: Date(),
            lastModifiedDate: Date()
        )
    }
    
    // MARK: - Recipe Management
    /// Saves the recipe and its category relationships. Returns `true` on success;
    /// on failure, sets `showingSaveErrorAlert` so the view can inform the user.
    @discardableResult
    func saveRecipe() async -> Bool {
        // Convert text to structured data before saving
        convertTextToStructuredData()

        recipe.lastModifiedDate = Date()

        // Copy main-actor state into locals for use inside the @Sendable DB closure
        let recipeToSave = recipe
        let categoryIDsToSave = selectedCategoryIDs

        do {
            try await database.write { db in
                // First, save the recipe
                try Recipe.insert { recipeToSave }.execute(db)

                // Then, save the category relationships
                for categoryId in categoryIDsToSave {
                    let recipeCategory = RecipeCategory(
                        id: UUID().uuidString,
                        recipeId: recipeToSave.id,
                        categoryId: categoryId
                    )
                    try RecipeCategory.insert { recipeCategory }.execute(db)
                }
            }
            logger.info("Recipe saved successfully: \(self.recipe.id) with \(self.selectedCategoryIDs.count) categories")
            recipeWasSaved = true
            // Tell main window to select and scroll to the new recipe (lives in
            // separate window on macOS, so can't be done through shared state).
            NotificationCenter.default.post(
                name: .recipeImportedFromWeb,
                object: nil,
                userInfo: ["recipeId": recipeToSave.id]
            )
            return true
        } catch {
            logger.error("Error saving recipe: \(error)")
            saveErrorMessage = error.localizedDescription
            showingSaveErrorAlert = true
            return false
        }
    }

    /// Prepares the in-memory recipe for hand-off to the structured editor by
    /// converting any pasted/extracted text into structured ingredients and directions.
    func prepareRecipeForEditing() {
        convertTextToStructuredData()
    }

    /// Downloads the recipe photo from a scanned image URL and attaches it to the recipe
    /// via the app's standard image pipeline (which also generates the thumbnail).
    /// Failures are non-fatal: the recipe simply imports without a photo.
    func downloadAndAttachImage(from urlString: String?) async {
        guard let urlString, !urlString.isEmpty else { return }

        let importer = SchemaOrgRecipeJSONLDImporter()
        guard let imageData = await importer.downloadImageData(from: urlString) else {
            logger.info("No usable recipe photo downloaded; importing without an image")
            return
        }
        guard !importSessionEnded else {
            logger.info("Import session ended before photo download finished; discarding it")
            return
        }
        recipe.setImage(imageData)
        logger.info("Attached imported recipe photo (\(imageData.count) bytes)")
    }

    /// Deletes the downloaded photo when the import session ends without the recipe having been
    /// saved, so a discarded import doesn't leave an orphaned file in image storage. Safe to call
    /// from any dismissal path: it does nothing once the recipe is saved or if no photo is attached.
    func cleanUpUnsavedImage() {
        // Mark the session over first, so an in-flight photo download can't attach (and
        // re-create the file) after this cleanup runs.
        importSessionEnded = true
        guard !recipeWasSaved, recipe.imageFilename != nil else { return }
        let recipeId = recipe.id
        Task {
            do {
                // Belt and braces: never delete the photo of a recipe that made it into the database.
                let recipeExists = try await database.read { db in
                    try Recipe.where { $0.id.eq(recipeId) }.fetchOne(db) != nil
                }
                if !recipeExists {
                    logger.info("Import discarded; deleting unsaved recipe photo")
                    recipe.removeImage()
                }
            } catch {
                // Leave the file for the orphaned-image cleanup task rather than risk deleting
                // a photo we can't verify.
                logger.error("Could not verify recipe before image cleanup: \(error)")
            }
        }
    }

    private func convertTextToStructuredData() {
        // Convert ingredients text to structured ingredients
        if !ingredientsText.isEmpty {
            recipe.ingredients = IngredientTextParser.parseIngredients(from: ingredientsText)
        }
        
        // Convert directions text to structured directions
        if !directionsText.isEmpty {
            recipe.directions = DirectionTextParser.parseDirections(from: directionsText)
        }
    }

    
    func resetRecipe() {
        recipe = Recipe(
            id: UUIDV7().uuidString,
            name: "",
            createdDate: Date(),
            lastModifiedDate: Date()
        )
        ingredientsText = ""
        directionsText = ""
    }
    
    func populateFromScannedRecipe(_ scannedRecipe: Recipe) {
        logger.info("Populating recipe from scanned data: \(scannedRecipe.name)")
        
        // Update basic recipe fields
        recipe.name = scannedRecipe.name
        recipe.source = scannedRecipe.source
        recipe.sourceDetails = scannedRecipe.sourceDetails
        recipe.introduction = scannedRecipe.introduction
        recipe.yield = scannedRecipe.yield
        recipe.servings = scannedRecipe.servings
        recipe.rating = scannedRecipe.rating
        recipe.difficulty = scannedRecipe.difficulty
        recipe.preparationTimes = scannedRecipe.preparationTimes
        recipe.notes = scannedRecipe.notes
        recipe.nutrition = scannedRecipe.nutrition
        recipe.lastModifiedDate = Date()
        
        // Convert structured ingredients to text
        if !scannedRecipe.ingredients.isEmpty {
            ingredientsText = scannedRecipe.ingredients.map { $0.text }.joined(separator: "\n")
        }
        
        // Convert structured directions to text
        if !scannedRecipe.directions.isEmpty {
            directionsText = scannedRecipe.directions.map { $0.text }.joined(separator: "\n\n")
        }
        
        logger.info("Successfully populated recipe with \(scannedRecipe.ingredients.count) ingredients and \(scannedRecipe.directions.count) directions")
    }
    
    // MARK: - Text Extraction Methods
    func extractTextToField(_ text: String, field: RecipeField) {
        let cleanText = decodeHTMLEntities(text.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !cleanText.isEmpty else { 
            logger.warning("Empty text provided for \(field.rawValue)")
            return 
        }
        
        logger.info("Extracting text to \(field.rawValue): \(String(cleanText.prefix(100)))")
        
        switch field {
        case .name:
            recipe.name = cleanText
        case .source:
            recipe.source = cleanText
        case .sourceDetails:
            recipe.sourceDetails = cleanText
        case .servings:
            // Try to extract numeric value
            if let servings = Int(cleanText.filter { $0.isNumber }) {
                recipe.servings = servings
            }
        case .yield:
            recipe.yield = cleanText
        case .introduction:
            recipe.introduction = cleanText
        case .ingredients:
            appendToIngredientsText(cleanText)
        case .directions:
            appendToDirectionsText(cleanText)
        }
        
        logger.info("Successfully extracted text to \(field.rawValue): \(String(cleanText.prefix(100)))")
        
    }
    
    private func appendToIngredientsText(_ text: String) {
        if !ingredientsText.isEmpty {
            ingredientsText += "\n"
        }
        ingredientsText += text
    }
    
    private func appendToDirectionsText(_ text: String) {
        if !directionsText.isEmpty {
            directionsText += "\n"
        }
        directionsText += text
    }
    
    // MARK: - URL Navigation
    func navigateToURL(_ url: String) {
        var urlString = url.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Don't navigate if URL is empty or the same as current
        guard !urlString.isEmpty && urlString != currentURL else { return }
        
        // Add https:// if no protocol specified
        if !urlString.hasPrefix("http://") && !urlString.hasPrefix("https://") {
            urlString = "https://" + urlString
        }
        
        // Only update if the normalized URL is different
        if urlString != currentURL {
            currentURL = urlString
        }
    }
    
    func refreshCurrentPage() {
        // This will be handled by the web view
    }
    
    // MARK: - Helper Methods
    func updateNavigationState(canGoBack: Bool, canGoForward: Bool, isLoading: Bool) {
        self.canGoBack = canGoBack
        self.canGoForward = canGoForward
        self.isLoading = isLoading
    }
    
    func openRecipeEditorForNewRecipe() {
        // This will be called after saving the recipe to open the editor
        // The recipe editor will be opened by the parent view
        logger.info("Recipe saved, ready to open editor for: \(self.recipe.id)")
    }
    
    /// Decodes common HTML entities that might appear in scraped content
    private func decodeHTMLEntities(_ text: String) -> String {
        return text
            .replacingOccurrences(of: "&apos;", with: "'")
            .replacingOccurrences(of: "&#39;", with: "'")
            .replacingOccurrences(of: "&#x27;", with: "'")
            .replacingOccurrences(of: "&quot;", with: "\"")
            .replacingOccurrences(of: "&#34;", with: "\"")
            .replacingOccurrences(of: "&amp;", with: "&")
            .replacingOccurrences(of: "&lt;", with: "<")
            .replacingOccurrences(of: "&gt;", with: ">")
    }
}

// MARK: - Recipe Field Enum
enum RecipeField: String, CaseIterable {
    case name = "Recipe Name"
    case source = "Source"
    case sourceDetails = "Source Details"
    case servings = "Servings"
    case yield = "Yield"
    case introduction = "Introduction"
    case ingredients = "Ingredients"
    case directions = "Directions"
    
    var shortcutKey: String {
        switch self {
        case .name: return "1"
        case .source: return "2"
        case .sourceDetails: return "3"
        case .servings: return "4"
        case .yield: return "7"
        case .introduction: return "8"
        case .ingredients: return "5"
        case .directions: return "6"
        }
    }
} 
