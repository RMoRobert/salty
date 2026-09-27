//
//  RecipeFileImportHelper.swift
//  Salty
//
//  Imports .saltyRecipe, .mgourmet and .crumb files. Decoding and inserting are SaltyCore's
//  (`RecipeImportFile`, `SaltyRecipeImporter`, shared with the C# app); this is the app's part: reading
//  the file, attaching the photo with the app's thumbnailer, and reporting what landed.
//

import Foundation
import OSLog
import SQLiteData
import SaltyCore

enum RecipeFileImportHelper {
    private static let logger = Logger(subsystem: "Salty", category: "App")

    /// Best-effort peek of the recipe name(s) in a file, for a confirmation prompt before importing an
    /// opened or AirDropped file. [] if the file can't be read or isn't a recipe file Salty imports.
    static func peekRecipeNames(_ fileUrl: URL) -> [String] {
        guard let kind = RecipeImportFileKind(url: fileUrl),
              let data = Data.contents(of: fileUrl, maxBytes: ImportFileLimits.maxRecipeFileBytes)
        else {
            return []
        }
        return (try? RecipeImportFile.decode(data, kind: kind))?.map(\.name) ?? []
    }

    /// Imports the recipes in a recipe file, its format chosen by its extension, and returns the ids of
    /// those inserted, in file order. Each recipe gets its own transaction, so one failure is logged and
    /// skipped rather than costing the rest of the file.
    @discardableResult
    static func importIntoDatabase(_ database: any DatabaseWriter, fileUrl: URL) async throws -> [String] {
        guard let kind = RecipeImportFileKind(url: fileUrl) else {
            throw ImportError.decodingFailed(RecipeImportFileError.unsupportedFileType(fileUrl.pathExtension))
        }

        // Crouton embeds full-size JPEGs as base64, so recipe files run to several MB apiece; the cap
        // is here to stop a pathological file, not a normal one.
        guard let data = Data.contents(of: fileUrl, maxBytes: ImportFileLimits.maxRecipeFileBytes) else {
            logger.error("No data found in \(fileUrl.lastPathComponent)")
            throw ImportError.noDataFound
        }

        let exports: [SaltyRecipeExport]
        do {
            exports = try RecipeImportFile.decode(data, kind: kind)
        } catch {
            logger.error("Could not decode \(kind.displayName) file: \(error.localizedDescription)")
            throw ImportError.decodingFailed(error)
        }
        logger.info("Found \(exports.count) \(kind.displayName) recipes to import")

        var insertedIds: [String] = []
        for export in exports {
            do {
                let id = try await database.write { db -> String in
                    let now = Date()
                    var recipe = try SaltyRecipeImporter.insert(export, in: db, now: now)

                    // The photo goes on afterwards: its file is named for the recipe's new id, and its
                    // thumbnail needs this app's image code. If it can't be written the recipe imports without it.
                    if let imageData = export.imageData {
                        recipe.setImage(imageData)
                        try RecipeWriter.save(recipe, in: db, now: now)
                    }
                    return recipe.id
                }
                insertedIds.append(id)
            } catch {
                logger.error("Failed to import recipe '\(export.name)': \(error.localizedDescription)")
            }
        }

        logger.info("Import completed: \(insertedIds.count) of \(exports.count) recipes imported")
        return insertedIds
    }
}
