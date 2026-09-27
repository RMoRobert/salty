//
//  SaltyRecipeImporter.swift
//  SaltyCore
//
//  Adds an imported recipe to the library: fresh ids (re-importing an export makes a copy, not an
//  overwrite), course/categories/tags matched by name or created, stamped as a change made now.
//
//  The photo is the caller's to attach: its thumbnail needs an image codec, which SaltyCore has only
//  on Apple platforms.
//

import Foundation
import GRDB

public enum SaltyRecipeImporter {

    /// Inserts `export` as a new recipe inside the caller's transaction and returns it as stored.
    @discardableResult
    public static func insert(_ export: SaltyRecipeExport, in db: Database, now: Date = Date()) throws -> Recipe {
        var recipe = export.convertToRecipe()
        if let course = export.course {
            recipe.courseId = try LibraryClassifierResolver.resolveId(kind: .course, name: course, in: db)
        }
        let stored = try RecipeWriter.insertImported(recipe, in: db, now: now)

        let categoryIds = try (export.categories ?? []).compactMap {
            try LibraryClassifierResolver.resolveId(kind: .category, name: $0, in: db)
        }
        let tagIds = try (export.tags ?? []).compactMap {
            try LibraryClassifierResolver.resolveId(kind: .tag, name: $0, in: db)
        }
        // Same `now` as the insert, so this can only restamp the recipe with the value it already has.
        try RecipeClassificationWriter.set(categoryIds: categoryIds, tagIds: tagIds, forRecipe: stored.id, in: db, now: now)
        return stored
    }
}
