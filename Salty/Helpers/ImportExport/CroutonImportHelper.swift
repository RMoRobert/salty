//
//  CroutonImportHelper.swift
//  Salty
//
//  Created by Robert on 8/15/26.
//

import Foundation
import SQLiteData
import SaltyCore
import OSLog

struct CroutonImportHelper: RecipeFileImporterProtocol {
    private static let logger = Logger(subsystem: "Salty", category: "App")

    /// Best-effort peek of the recipe name(s) in a .crumb file, for a confirmation prompt before
    /// importing an opened/AirDropped file. Returns [] if the file can't be read or decoded.
    static func peekRecipeNames(_ fileUrl: URL) -> [String] {
        guard let data = Data.contents(of: fileUrl, maxBytes: ImportFileLimits.maxRecipeFileBytes) else { return [] }
        return (try? decodeRecipes(from: data))?.map(\.name) ?? []
    }

    /// Imports the recipes in a .crumb file and returns the ids of those inserted (in file order).
    @discardableResult
    static func importIntoDatabase(_ database: any DatabaseWriter, fileUrl: URL) async throws -> [String] {
        // Crouton embeds full-size JPEGs as base64, so recipe files run to several MB apiece; the cap
        // is here to stop a pathological file, not a normal one.
        guard let data = Data.contents(of: fileUrl, maxBytes: ImportFileLimits.maxRecipeFileBytes) else {
            logger.error("No Crouton data found in file; returning")
            throw ImportError.noDataFound
        }

        let croutonRecipes: [CroutonImportRecipe]
        do {
            croutonRecipes = try decodeRecipes(from: data)
        } catch {
            logger.error("Could not decode Crouton file. Error: \(error.localizedDescription)")
            throw ImportError.decodingFailed(error)
        }
        logger.info("Found \(croutonRecipes.count) Crouton recipes to import")

        var successCount = 0
        var failureCount = 0
        var insertedIds: [String] = []

        for croutonRecipe in croutonRecipes {
            do {
                let newId = try await database.write { db -> String in
                    var imgData: Data?
                    var tags: [String]?
                    var recipe = croutonRecipe.convertToRecipe(imageData: &imgData, tags: &tags)

                    try Recipe.insert { recipe }.execute(db)

                    // Save image if present (this needs to happen after recipe is saved)
                    if let imgData {
                        recipe.setImage(imgData)
                        try Recipe.update(recipe).execute(db)
                    }

                    // Save tags if present
                    if let tags {
                        // Use a Set to deduplicate tag names
                        for tagName in Set(tags) {
                            // Reuses an existing tag whose name differs only in case or spacing,
                            // rather than creating a near-duplicate row.
                            guard let tagId = try LibraryItemResolver.resolveId(kind: .tag, name: tagName, in: db) else {
                                continue
                            }

                            let existingRelationship = try RecipeTag
                                .where { $0.recipeId.eq(recipe.id) && $0.tagId.eq(tagId) }
                                .fetchOne(db)

                            if existingRelationship == nil {
                                let recipeTag = RecipeTag(id: UUID().uuidString, recipeId: recipe.id, tagId: tagId)
                                try RecipeTag.insert { recipeTag }.execute(db)
                            }
                        }
                    }

                    return recipe.id
                }
                insertedIds.append(newId)
                successCount += 1
            } catch {
                failureCount += 1
                logger.error("Failed to import recipe '\(croutonRecipe.name)': \(error.localizedDescription)")
            }
        }

        logger.info("Import completed: \(successCount) successful, \(failureCount) failed")
        return insertedIds
    }

    /// A `.crumb` file holds one recipe object, but an array is accepted too so a hand-assembled or
    /// future multi-recipe file still imports.
    private static func decodeRecipes(from data: Data) throws -> [CroutonImportRecipe] {
        let decoder = JSONDecoder()
        if let many = try? decoder.decode([CroutonImportRecipe].self, from: data) {
            return many
        }
        return [try decoder.decode(CroutonImportRecipe.self, from: data)]
    }
}
