//
//  RecipeImageWriter.swift
//  SaltyCore
//
//  Setting and clearing a recipe's photo: the file in the library's recipeImages folder, and the row's
//  image columns with `lastModifiedImageDate`, through `RecipeWriter.save` so the stamp follows its one
//  rule. The Apple app does this with RecipeImageManager and Recipe.setImage; this is the same shape for
//  a client with no UIImage/NSImage.
//
//  The thumbnail is always the caller's: making one needs an image codec, and SaltyCore has none off
//  Apple platforms.
//

import Foundation
import GRDB

public enum RecipeImageWriter {

    /// Stores `data` as the recipe's photo, file first and then the row, and returns the recipe as saved.
    ///
    /// The file is `<recipeId>.<ext>`, the name every Salty client uses, with the extension read from the
    /// bytes (falling back to `fileExtension`, then jpg). `thumbnail` becomes `imageThumbnailData`; nil
    /// stores none, which is still right, since the old one pictured the old photo.
    ///
    /// Other `<recipeId>.*` files are left alone here; remove them with `deleteFiles(forRecipe:except:)`
    /// after the transaction commits, so a rolled-back write never costs the photo it was replacing.
    public static func setImage(
        _ data: Data,
        fileExtension: String? = nil,
        thumbnail: Data?,
        forRecipe recipeId: String,
        imagesDirectory: URL,
        in db: Database,
        now rawNow: Date = Date()
    ) throws -> Recipe {
        guard LibraryFilenames.isSafeComponent(recipeId) else { throw RecipeWriterError.unsafeRecipeId(recipeId) }
        guard var recipe = try Recipe.where({ $0.id.eq(recipeId) }).fetchOne(db) else {
            throw RecipeWriterError.recipeNotFound(recipeId)
        }

        let filename = "\(recipeId).\(ImageDataFormat.detect(data)?.fileExtension ?? cleanExtension(fileExtension) ?? "jpg")"
        try FileManager.default.createDirectory(at: imagesDirectory, withIntermediateDirectories: true)
        try data.write(to: imagesDirectory.appending(path: filename), options: .atomic)

        let now = rawNow.roundedToWireMillis
        recipe.imageFilename = filename
        recipe.imageThumbnailData = thumbnail
        // A floor RecipeWriter raises to `now`: the file name is usually unchanged by a replacement, so
        // the stamp can't be left to a diff of the row (see RecipeWriter.save).
        recipe.lastModifiedImageDate = now
        return try RecipeWriter.save(recipe, in: db, now: now).recipe
    }

    /// Removes the recipe's photo from its row, stamping `lastModifiedImageDate` so the removal syncs
    /// rather than being undone by the next sync. Returns the recipe as saved; delete the files with
    /// `deleteFiles(forRecipe:except:)` after the transaction commits.
    public static func clearImage(forRecipe recipeId: String, in db: Database, now rawNow: Date = Date()) throws -> Recipe {
        guard var recipe = try Recipe.where({ $0.id.eq(recipeId) }).fetchOne(db) else {
            throw RecipeWriterError.recipeNotFound(recipeId)
        }
        let now = rawNow.roundedToWireMillis
        recipe.imageFilename = nil
        recipe.imageThumbnailData = nil
        recipe.lastModifiedImageDate = now
        return try RecipeWriter.save(recipe, in: db, now: now).recipe
    }

    /// Deletes every `<recipeId>.*` file but `keep`: a replacement stored under a different extension,
    /// or a stray left by an interrupted sync, would otherwise stay in the library for good.
    public static func deleteFiles(forRecipe recipeId: String, except keep: String?, imagesDirectory: URL) {
        guard LibraryFilenames.isSafeComponent(recipeId),
              let contents = try? FileManager.default.contentsOfDirectory(atPath: imagesDirectory.path(percentEncoded: false))
        else { return }
        for filename in contents where filename.hasPrefix("\(recipeId).") && filename != keep {
            try? FileManager.default.removeItem(at: imagesDirectory.appending(path: filename))
        }
    }

    private static func cleanExtension(_ fileExtension: String?) -> String? {
        let cleaned = (fileExtension ?? "").trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: ".")).lowercased()
        return !cleaned.isEmpty && cleaned.allSatisfy { $0.isLetter || $0.isNumber } ? cleaned : nil
    }
}
