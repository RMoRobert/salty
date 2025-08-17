//
//  SaltyRecipeImportHelper.swift
//  Salty
//
//  Created by Robert on 8/16/25.
//

import Foundation
import SharingGRDB
import OSLog

struct SaltyRecipeImportHelper: RecipeFileImporterProtocol {
    private static let logger = Logger(subsystem: "Salty", category: "App")
    
    static func importIntoDatabase(_ database: any DatabaseWriter, jsonFileUrl: URL) async {
        guard let jsonData = getDataFromFile(jsonFileUrl) else {
            logger.error("No JSON data found in file; returning")
            return
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
                        try recipe.insert(db)
                        
                        // Save image if present (this needs to happen after recipe is saved)
                        if let imageData = saltyRecipe.imageData {
                            recipe.setImage(imageData)
                            // Update the recipe in database with image info
                            try recipe.update(db)
                        }
                        
                        // Save categories if present
                        if let categories = saltyRecipe.categories {
                            // Use a Set to deduplicate category names
                            let uniqueCategories = Set(categories)
                            
                            for categoryName in uniqueCategories {
                                // Find existing category or create new one
                                var category = try Category.filter(Column("name") == categoryName).fetchOne(db)
                                if category == nil {
                                    category = Category(id: UUID().uuidString, name: categoryName)
                                    try category!.insert(db)
                                }
                                
                                guard let category = category else { continue }
                                
                                // Check if relationship already exists before creating it
                                let existingRelationship = try RecipeCategory
                                    .filter(Column("recipeId") == recipe.id && Column("categoryId") == category.id)
                                    .fetchOne(db)
                                
                                if existingRelationship == nil {
                                    // Create relationship only if it doesn't already exist
                                    let recipeCategory = RecipeCategory(id: UUID().uuidString, recipeId: recipe.id, categoryId: category.id)
                                    try recipeCategory.insert(db)
                                }
                            }
                        }
                        
                        // Save tags if present
                        if let tags = saltyRecipe.tags {
                            // Use a Set to deduplicate tag names
                            let uniqueTags = Set(tags)
                            
                            for tagName in uniqueTags {
                                // Find existing tag or create new one
                                var tag = try Tag.filter(Column("name") == tagName).fetchOne(db)
                                if tag == nil {
                                    tag = Tag(id: UUID().uuidString, name: tagName)
                                    try tag!.insert(db)
                                }
                                
                                guard let tag = tag else { continue }
                                
                                // Check if relationship already exists before creating it
                                let existingRelationship = try RecipeTag
                                    .filter(Column("recipeId") == recipe.id && Column("tagId") == tag.id)
                                    .fetchOne(db)
                                
                                if existingRelationship == nil {
                                    // Create relationship only if it doesn't already exist
                                    let recipeTag = RecipeTag(id: UUID().uuidString, recipeId: recipe.id, tagId: tag.id)
                                    try recipeTag.insert(db)
                                }
                            }
                        }
                        
                        // Set course if present
                        if let courseName = saltyRecipe.course, !courseName.isEmpty {
                            // Check for existing course or create new one
                            var course = try Course.filter(Column("name") == courseName).fetchOne(db)
                            if course == nil {
                                course = Course(id: UUID().uuidString, name: courseName)
                                try course!.insert(db)
                            }
                            // Set the recipe's courseId if found or inserted
                            if let course = course {
                                recipe.courseId = course.id
                                try recipe.update(db)
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
        }
    }
}
