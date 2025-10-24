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
    
    static func importIntoDatabase(_ database: any DatabaseWriter, jsonFileUrl: URL) async throws {
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
            
            for saltyRecipe in saltyRecipes {
                do {
                    try await database.write { db in
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
                                var category = try Category.where { $0.name == categoryName }.fetchOne(db)
                                if category == nil {
                                    category = Category(id: UUID().uuidString, name: categoryName)
                                    try Category.insert {
                                        category!
                                    }.execute(db)
                                }
                                
                                guard let category = category else { continue }
                                
                                // Check if relationship already exists before creating it
                                let existingRelationship = try RecipeCategory
                                    .where { $0.recipeId == recipe.id && $0.categoryId == category.id }
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
                                var tag = try Tag.where { $0.name == tagName }.fetchOne(db)
                                if tag == nil {
                                    tag = Tag(id: UUID().uuidString, name: tagName)
                                    try Tag.insert{ tag! }.execute(db)
                                }
                                
                                guard let tag = tag else { continue }
                                
                                // Check if relationship already exists before creating it
                                let existingRelationship = try RecipeTag
                                    .where { $0.recipeId == recipe.id && $0.tagId == tag.id }
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
                            var course = try Course.where { $0.name == courseName }.fetchOne(db)
                            if course == nil {
                                course = Course(id: UUID().uuidString, name: courseName)
                                try Course.insert{ course! }.execute(db)
                            }
                            // Set the recipe's courseId if found or inserted
                            if let course = course {
                                recipe.courseId = course.id
                                try Recipe.update(recipe).execute(db)
                            }
                        }
                    }
                    successCount += 1
                } catch {
                    failureCount += 1
                    logger.error("Failed to import recipe '\(saltyRecipe.name)': \(error.localizedDescription)")
                }
            }
            
            logger.info("Import completed: \(successCount) successful, \(failureCount) failed")
        } catch {
            logger.error("Could not decode Salty recipe file. Error: \(error.localizedDescription)")
            throw ImportError.decodingFailed(error)
        }
    }
}
