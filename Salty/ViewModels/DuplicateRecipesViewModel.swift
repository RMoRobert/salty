//
//  DuplicateRecipesViewModel.swift
//  Salty
//
//  Backs DuplicateRecipesView: finds recipes whose content is identical and lists them, grouped.
//  Nothing is merged or removed automatically — the only mutation here is a delete the user asks for
//  explicitly, one row or one selection at a time.
//

import Foundation
import OSLog
import SQLiteData
import SaltyCore

@Observable
@MainActor
final class DuplicateRecipesViewModel {
    private let logger = Logger(subsystem: "Salty", category: "Database")

    @ObservationIgnored
    @Dependency(\.defaultDatabase) private var database

    /// Groups from the most recent scan, ordered by name.
    private(set) var groups: [RecipeDuplicateGroup] = []
    /// The strictness the last scan used, so the summary line describes what's actually on screen.
    private(set) var matchLevel: RecipeDuplicateMatchLevel = .defaultLevel
    var selectedRecipeIDs: Set<String> = []
    private(set) var isScanning = false
    /// False until the first scan finishes, so the empty state isn't shown before there's an answer.
    private(set) var hasScanned = false
    /// Recipes a pending delete applies to — one row, or the whole selection.
    var deleteCandidateIDs = Set<String>()
    var showingDeleteConfirmation = false
    var operationError: String?

    // MARK: - Derived state

    var duplicateRecipeCount: Int {
        groups.reduce(0) { $0 + $1.recipes.count }
    }

    /// "8 total recipes in 3 groups. Matching on title, source, ingredients, and directions" -- the status
    /// line under the list, which has to say what was compared for the count to mean anything.
    var summaryText: String {
        let recipes = duplicateRecipeCount
        let sets = groups.count
        let counts = "\(recipes) total recipe\(recipes == 1 ? "" : "s") in \(sets) group\(sets == 1 ? "" : "s")"
        return "\(counts). \(matchLevel.summaryDescription)"
    }

    // MARK: - Actions

    /// Re-reads every recipe and regroups at the given strictness (the last one used, if omitted).
    /// Full rows are needed — the whole point is comparing content — so this decodes the JSON columns
    /// the main list deliberately skips: fine for a command the user runs on demand, but not something
    /// to put on a hot path.
    func scan(level: RecipeDuplicateMatchLevel? = nil) async {
        let level = level ?? matchLevel
        isScanning = true
        defer { isScanning = false }
        do {
            let allRecipes = try await database.read { db in
                try Recipe.fetchAll(db)
            }
            matchLevel = level
            groups = RecipeDuplicateFinder.groups(in: allRecipes, level: level)
            // Drop anything from the selection that's no longer listed (deleted, or edited so that it
            // is no longer a duplicate).
            let visibleIDs = Set(groups.flatMap { $0.recipes.map(\.id) })
            selectedRecipeIDs.formIntersection(visibleIDs)
            hasScanned = true
        } catch {
            logger.error("Error scanning for duplicate recipes: \(error)")
            operationError = "Couldn’t scan for duplicate recipes. \(error.localizedDescription)"
        }
    }

    func confirmDelete(ids: Set<String>) {
        guard !ids.isEmpty else { return }
        deleteCandidateIDs = ids
        showingDeleteConfirmation = true
    }

    /// Deletes the recipes a confirmed delete applies to, removing their image files first (the same
    /// order the main recipe list uses — the row is what makes the file reachable).
    func deleteConfirmedRecipes() async {
        let ids = deleteCandidateIDs
        guard !ids.isEmpty else { return }
        do {
            let imageFilenames = try await database.read { db in
                try Recipe
                    .select { $0.imageFilename }
                    .where { $0.id.in(ids) }
                    .fetchAll(db)
            }
            for case let filename? in imageFilenames {
                RecipeImageManager.shared.deleteImage(filename: filename)
            }
            try await database.write { db in
                try Recipe.where { $0.id.in(ids) }.delete().execute(db)
                // Tombstoned like any other deletion: consolidating duplicates is still a deletion, and
                // without this the copies come back on the next sync from a peer. See
                // RecipeTombstoneWriter.
                try RecipeTombstoneWriter.recordDeletions(Array(ids), in: db)
            }
            selectedRecipeIDs.subtract(ids)
            deleteCandidateIDs.removeAll()
            await scan()
        } catch {
            logger.error("Error deleting duplicate recipes: \(error)")
            operationError = "Couldn’t delete the selected recipe\(ids.count == 1 ? "" : "s"). \(error.localizedDescription)"
        }
    }
}
