//
//  RecipeDetailEditViewModel.swift
//  Salty
//
//  Created by Robert on 7/9/25.
//

import Foundation
import OSLog
import SQLiteData
import SaltyCore

@Observable
@MainActor
class RecipeDetailEditViewModel {
    private let logger = Logger(subsystem: "Salty", category: "Database")

    @ObservationIgnored
    @Dependency(\.defaultDatabase) private var database

    @ObservationIgnored
    @FetchAll(#sql("SELECT \(Course.columns) FROM \(Course.self) ORDER BY \(Course.name) COLLATE NOCASE"))
    var allCourses: [Course]

    @ObservationIgnored
    @FetchAll(#sql("SELECT \(Category.columns) FROM \(Category.self) ORDER BY \(Category.name) COLLATE NOCASE"))
    var allCategories: [Category]

    @ObservationIgnored
    @FetchAll(#sql("SELECT \(Tag.columns) FROM \(Tag.self) ORDER BY \(Tag.name) COLLATE NOCASE"))
    var allTags: [Tag]

    // MARK: - State
    var recipe: Recipe
    var originalRecipe: Recipe
    var isNewRecipe: Bool
    var onNewRecipeSaved: ((String) -> Void)?

    // MARK: - Classification State
    /// The categories and tags this editor will save, held until Save like every other edit. Loaded
    /// from the database by `loadClassification()` once the editor is on screen; a new recipe starts
    /// with none. See `RecipeClassificationDraft`.
    var classification = RecipeClassificationDraft()
    private var originalClassification = RecipeClassificationDraft()

    // MARK: - Image State
    /// The image change the editor is holding until Save. Nothing touches the image file on disk
    /// before then, which is what lets Cancel actually cancel. See `PendingRecipeImage`.
    var pendingImage: PendingRecipeImage = .unchanged

    // MARK: - Sheet States
    // May want to name more generically in future, or somehow accomodate mobile if do navigation instead of popovers/sheets?
    var showingEditCategoriesSheet = false
    var showingBulkEditIngredientsSheet = false
    var showingBulkEditDirectionsSheet = false
    var showingNutritionEditSheet = false
    var showingScanTextSheet = false
    var scanTextTarget: ScanTextTarget = .ingredients
    var showingCancelAlert = false
    var showingSaveErrorAlert = false
    var saveErrorMessage: String?

    enum ScanTextTarget: String, CaseIterable {
        case introduction = "Introduction"
        case ingredients = "Ingredients"
        case directions = "Directions"
    }

    // MARK: - Computed Properties
    var hasUnsavedChanges: Bool {
        if pendingImage.isChange || classification != originalClassification || recipe != originalRecipe {
            return true
        }
        // Cancelling a new recipe throws the whole recipe away, not just the edits made since it
        // opened -- so one that arrived with content (from an import) is worth asking about too.
        return isNewRecipe && (
            !recipe.name.isEmpty || !recipe.source.isEmpty || !recipe.introduction.isEmpty ||
            !recipe.ingredients.isEmpty || !recipe.directions.isEmpty || !recipe.notes.isEmpty || !recipe.variations.isEmpty
        )
    }

    var sortedTags: [String] {
        classification.tagNames(in: allTags)
    }

    var hasTags: Bool {
        !sortedTags.isEmpty
    }

    var sortedCategories: [String] {
        classification.categoryNames(in: allCategories)
    }

    var hasCategories: Bool {
        !sortedCategories.isEmpty
    }

    // MARK: - Initialization
    init(recipe: Recipe, isNewRecipe: Bool = false, onNewRecipeSaved: ((String) -> Void)? = nil) {
        self.recipe = recipe
        self.originalRecipe = recipe
        self.isNewRecipe = isNewRecipe
        self.onNewRecipeSaved = onNewRecipeSaved
    }

    // MARK: - Loading

    /// Reads the recipe's stored categories and tags into the draft. Called from the editor's `.task`;
    /// a draft the user has already touched by then is left alone, only its baseline is set.
    func loadClassification() async {
        let recipeId = recipe.id
        do {
            let stored = try await database.read { db -> RecipeClassificationDraft in
                let categoryIds = try RecipeCategory.where { $0.recipeId.eq(recipeId) }.fetchAll(db).map(\.categoryId)
                let tagIds = try RecipeTag.where { $0.recipeId.eq(recipeId) }.fetchAll(db).map(\.tagId)
                return RecipeClassificationDraft(categoryIDs: Set(categoryIds), tagIDs: Set(tagIds))
            }
            let untouched = classification == originalClassification
            originalClassification = stored
            if untouched {
                classification = stored
            }
        } catch {
            logger.error("Error loading the recipe's categories and tags: \(error)")
        }
    }

    // MARK: - Public Methods
    /// Saves the recipe and its category relationships. Returns `true` on success;
    /// on failure, sets `showingSaveErrorAlert` so the view can inform the user.
    @discardableResult
    func saveRecipe() async -> Bool {
        // Snapshot main-actor state into locals: the async write closure is @Sendable and runs
        // off the main actor, so it must not touch `self`. Sync timestamps are left to `RecipeWriter.save`.
        var recipeDraft = recipe
        let isNew = isNewRecipe
        let classificationDraft = classification
        let imagePolicy: RecipeWriter.BodySaveImage = pendingImage.isChange ? .useEdited : .keepStored
        let now = Date()

        // Apply the held image change now, on the copy that is about to be written: the new file goes
        // to disk first, the row pointing at it second, and the old file is removed last (below), so no
        // failure in between can leave the recipe without an image it still references.
        guard pendingImage.apply(to: &recipeDraft) else {
            logger.error("Could not write the recipe image; save aborted")
            saveErrorMessage = "The photo couldn't be saved to the recipe library."
            showingSaveErrorAlert = true
            return false
        }
        let recipeDraftToSave = recipeDraft
        do {
            // `save` returns the row as written, timestamps included.
            let (recipeToSave, savedTagIds) = try await database.write { db -> (Recipe, Set<String>) in
                // A body save keeps whatever photo and "last made" are stored now, so an editor opened
                // before a sync or another window changed them can't write the old values back; the
                // photo columns come from the draft only when this editor changed the photo itself. A
                // new recipe has no stored row to keep, so it is inserted. A recipe deleted elsewhere
                // while this editor was open surfaces as `recipeNotFound` rather than coming back.
                var recipeToSave = isNew
                    ? try RecipeWriter.save(recipeDraftToSave, in: db, now: now).recipe
                    : try RecipeWriter.saveBody(recipeDraftToSave, image: imagePolicy, in: db, now: now).recipe

                // Tags typed into this editor get their library rows now, found by the library's own
                // duplicate rule or created, so one that another device synced in meanwhile is reused.
                var tagIds = classificationDraft.tagIDs
                for name in classificationDraft.newTagNames {
                    if let tagId = try LibraryClassifierResolver.resolveId(kind: .tag, name: name, in: db, now: now) {
                        tagIds.insert(tagId)
                    }
                }

                // Membership travels on the recipe when it syncs, so the writer bumps the recipe's
                // clock when it changed anything; the row is read back so the editor holds that stamp.
                let changed = try RecipeClassificationWriter.set(
                    categoryIds: Array(classificationDraft.categoryIDs),
                    tagIds: Array(tagIds),
                    forRecipe: recipeToSave.id,
                    in: db,
                    now: now
                )
                if changed, let stamped = try Recipe.where({ $0.id.eq(recipeToSave.id) }).fetchOne(db) {
                    recipeToSave = stamped
                }
                return (recipeToSave, tagIds)
            }

            // The row is durable; now the file it stopped referencing (if any) can go.
            if pendingImage.isChange {
                recipeToSave.deleteStaleImageFiles()
            }

            // Handle successful save of new recipe
            if isNew {
                onNewRecipeSaved?(recipeToSave.id)
            }

            // After successful save, this is no longer a new recipe
            isNewRecipe = false
            recipe = recipeToSave
            originalRecipe = recipeToSave
            pendingImage = .unchanged
            let saved = RecipeClassificationDraft(categoryIDs: classificationDraft.categoryIDs, tagIDs: savedTagIds)
            classification = saved
            originalClassification = saved
            return true

        } catch {
            logger.error("Error saving recipe: \(error)")
            saveErrorMessage = error.localizedDescription
            showingSaveErrorAlert = true
            return false
        }
    }

    // MARK: - Tag Management

    /// Adds a tag to the draft; nothing reaches the database until Save.
    func addTag(_ tagName: String) {
        classification.addTag(named: tagName, library: allTags)
    }

    /// Removes a tag from the draft; nothing reaches the database until Save.
    func removeTag(_ tagName: String) {
        classification.removeTag(named: tagName, library: allTags)
    }

    func discardChanges() {
        recipe = originalRecipe
        pendingImage = .unchanged
        classification = originalClassification
    }

    var nutritionSummary: String? {
        guard let nutrition = recipe.nutrition else { return nil }

        var parts: [String] = []

        if let servingSize = nutrition.servingSize {
            parts.append("Serving Size: \(servingSize)")
        }
        if let calories = nutrition.calories {
            parts.append("Calories: \(calories.formatted())")
        }
        if let fat = nutrition.fat {
            parts.append("Total Fat: \(fat.formatted())g")
        }
        if let saturatedFat = nutrition.saturatedFat {
            parts.append("Saturated Fat: \(saturatedFat.formatted())g")
        }
        if let transFat = nutrition.transFat {
            parts.append("Trans Fat: \(transFat.formatted())g")
        }
        if let cholesterol = nutrition.cholesterol {
            parts.append("Cholesterol: \(cholesterol.formatted())mg")
        }
        if let sodium = nutrition.sodium {
            parts.append("Sodium: \(sodium.formatted())mg")
        }
        if let carbs = nutrition.carbohydrates {
            parts.append("Total Carbs: \(carbs.formatted())g")
        }
        if let fiber = nutrition.fiber {
            parts.append("Fiber: \(fiber.formatted())g")
        }
        if let sugar = nutrition.sugar {
            parts.append("Sugars: \(sugar.formatted())g")
        }
        if let protein = nutrition.protein {
            parts.append("Protein: \(protein.formatted())g")
        }

        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

}
