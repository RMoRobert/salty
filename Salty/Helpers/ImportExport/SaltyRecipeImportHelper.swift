//
//  SaltyRecipeImportHelper.swift
//  Salty
//
//  Created by Robert on 8/16/25.
//

import Foundation
import SQLiteData
import OSLog

struct SaltyRecipeImportHelper: RecipeFileImporterProtocol {
    private static let logger = Logger(subsystem: "Salty", category: "App")
    
    /// Best-effort peek of the recipe name(s) in a .saltyRecipe file, for a confirmation prompt before
    /// importing an opened/AirDropped file. Returns [] if the file can't be read or decoded.
    static func peekRecipeNames(_ jsonFileUrl: URL) -> [String] {
        guard let jsonData = getDataFromFile(jsonFileUrl) else { return [] }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        if let many = try? decoder.decode([SaltyRecipeExport].self, from: jsonData) {
            return many.map(\.name)
        }
        if let one = try? decoder.decode(SaltyRecipeExport.self, from: jsonData) {
            return [one.name]
        }
        return []
    }

    /// Imports the recipes in a .saltyRecipe file and returns the ids of those inserted (in file order).
    @discardableResult
    static func importIntoDatabase(_ database: any DatabaseWriter, jsonFileUrl: URL) async throws -> [String] {
        guard let jsonData = getDataFromFile(jsonFileUrl) else {
            logger.error("No JSON data found in file; returning")
            throw ImportError.noDataFound
        }
        
        do {
            // Configure JSON decoder to match the encoder settings
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            
            // Try to decode as array first (multiple recipes)
            var saltyRecipes: [SaltyRecipeExport]
            do {
                saltyRecipes = try decoder.decode([SaltyRecipeExport].self, from: jsonData)
                logger.info("Found \(saltyRecipes.count) Salty recipes to import")
            } catch {
                // If array decoding fails, try single recipe
                let singleRecipe = try decoder.decode(SaltyRecipeExport.self, from: jsonData)
                saltyRecipes = [singleRecipe]
                logger.info("Found 1 Salty recipe to import")
            }
            
            var successCount = 0
            var failureCount = 0
            var insertedIds: [String] = []

            for saltyRecipe in saltyRecipes {
                do {
                    let newId = try await database.write { db -> String in
                        var recipe = saltyRecipe.convertToRecipe()
                        
                        // Save the recipe
                        try Recipe.insert{ recipe }.execute(db)
                        
                        // Save image if present (this needs to happen after recipe is saved)
                        if let imageData = saltyRecipe.imageData {
                            recipe.setImage(imageData)
                            // Update the recipe in database with image info
                            try Recipe.update(recipe).execute(db)
                        }
                        
                        // Save categories if present
                        if let categories = saltyRecipe.categories {
                            // Use a Set to deduplicate category names
                            let uniqueCategories = Set(categories)
                            
                            for categoryName in uniqueCategories {
                                // Find existing category or create new one
                                let category: Category
                                if let existing = try Category.where { $0.name.eq(categoryName) }.fetchOne(db) {
                                    category = existing
                                } else {
                                    category = Category(id: UUID().uuidString, name: categoryName, lastModifiedDate: Date())
                                    try Category.insert { category }.execute(db)
                                }

                                // Check if relationship already exists before creating it
                                let existingRelationship = try RecipeCategory
                                    .where { $0.recipeId.eq(recipe.id) && $0.categoryId.eq(category.id) }
                                    .fetchOne(db)
                                
                                if existingRelationship == nil {
                                    // Create relationship only if it doesn't already exist
                                    let recipeCategory = RecipeCategory(id: UUID().uuidString, recipeId: recipe.id, categoryId: category.id)
                                    try RecipeCategory.insert {
                                        recipeCategory
                                    }.execute(db)
                                }
                            }
                        }
                        
                        // Save tags if present
                        if let tags = saltyRecipe.tags {
                            // Use a Set to deduplicate tag names
                            let uniqueTags = Set(tags)
                            
                            for tagName in uniqueTags {
                                // Find existing tag or create new one
                                let tag: Tag
                                if let existing = try Tag.where { $0.name.eq(tagName) }.fetchOne(db) {
                                    tag = existing
                                } else {
                                    tag = Tag(id: UUID().uuidString, name: tagName, lastModifiedDate: Date())
                                    try Tag.insert { tag }.execute(db)
                                }

                                // Check if relationship already exists before creating it
                                let existingRelationship = try RecipeTag
                                    .where { $0.recipeId.eq(recipe.id) && $0.tagId.eq(tag.id) }
                                    .fetchOne(db)
                                
                                if existingRelationship == nil {
                                    // Create relationship only if it doesn't already exist
                                    let recipeTag = RecipeTag(id: UUID().uuidString, recipeId: recipe.id, tagId: tag.id)
                                    try RecipeTag.insert{ recipeTag }.execute(db)
                                }
                            }
                        }
                        
                        // Set course if present
                        if let courseName = saltyRecipe.course, !courseName.isEmpty {
                            // Check for existing course or create new one
                            let course: Course
                            if let existing = try Course.where { $0.name.eq(courseName) }.fetchOne(db) {
                                course = existing
                            } else {
                                course = Course(id: UUID().uuidString, name: courseName, lastModifiedDate: Date())
                                try Course.insert { course }.execute(db)
                            }
                            // Set the recipe's courseId
                            recipe.courseId = course.id
                            try Recipe.update(recipe).execute(db)
                        }

                        return recipe.id
                    }
                    insertedIds.append(newId)
                    successCount += 1
                } catch {
                    failureCount += 1
                    logger.error("Failed to import recipe '\(saltyRecipe.name)': \(error.localizedDescription)")
                }
            }
            
            logger.info("Import completed: \(successCount) successful, \(failureCount) failed")
            return insertedIds
        } catch {
            logger.error("Could not decode Salty recipe file. Error: \(error.localizedDescription)")
            throw ImportError.decodingFailed(error)
        }
    }
}
