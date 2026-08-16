//
//  MacGourmetImportHelper.swift
//  Salty
//
//  Created by Robert on 6/1/23.
//

import Foundation
import SQLiteData
import SaltyCore
import OSLog

struct MacGourmetImportHelper: RecipeFileImporterProtocol {
    private static let logger = Logger(subsystem: "Salty", category: "App")
    
    /// Imports the recipes in a .mgourmet file and returns the ids of those inserted (in file order).
    @discardableResult
    static func importIntoDatabase(_ database: any DatabaseWriter, xmlFileUrl: URL) async throws -> [String] {
        guard let xmlData = getDataFromFile(xmlFileUrl) else {
            logger.error("No XML data found in file; returning")
            throw ImportError.noDataFound
        }
        
        do {
            let mgRecipes = try PropertyListDecoder().decode([MacGourmetImportRecipe].self, from: xmlData)
            logger.info("Found \(mgRecipes.count) MG recipes to import")
            
            var successCount = 0
            var failureCount = 0
            var insertedIds: [String] = []

            for mgRecipe in mgRecipes {
                do {
                    let newId = try await database.write { db -> String in
                        var imgData: Data?
                        var categories: [String]?
                        var recipe = mgRecipe.convertToRecipe(imageData: &imgData, categories: &categories)
                        
                        // Save the recipe
                        try Recipe.insert {
                            recipe
                        }.execute(db)
                        
                        // Save image if present (this needs to happen after recipe is saved)
                        if let imgData = imgData {
                            recipe.setImage(imgData)
                            // Update the recipe in database with image info
                            try Recipe.update(recipe).execute(db)
                        }
                        
                        // Save categories if present
                        if let categories = categories {
                            // Use a Set to deduplicate category names
                            let uniqueCategories = Set(categories)
                            
                            for categoryName in uniqueCategories {
                                // Reuses an existing category whose name differs only in case or
                                // spacing, rather than creating a near-duplicate row.
                                guard let categoryId = try LibraryItemResolver.resolveId(kind: .category, name: categoryName, in: db) else {
                                    continue
                                }

                                // Check if relationship already exists before creating it
                                let existingRelationship = try RecipeCategory
                                    .where { $0.recipeId.eq(recipe.id) && $0.categoryId.eq(categoryId) }
                                    .fetchOne(db)

                                if existingRelationship == nil {
                                    // Create relationship only if it doesn't already exist
                                    let recipeCategory = RecipeCategory(id: UUID().uuidString, recipeId: recipe.id, categoryId: categoryId)
                                    try RecipeCategory.insert {
                                        recipeCategory
                                    }.execute(db)
                                }
                            }
                        }
                        
                        // Set course if present
                        if let courseName = mgRecipe.courseName, !courseName.isEmpty, courseName != "--" {
                            if let courseId = try LibraryItemResolver.resolveId(kind: .course, name: courseName, in: db) {
                                // Set the recipe's courseId
                                recipe.courseId = courseId
                                try Recipe.update(recipe).execute(db)
                            }
                        }

                        return recipe.id
                    }
                    insertedIds.append(newId)
                    successCount += 1
                } catch {
                    failureCount += 1
                    logger.error("Failed to import recipe '\(mgRecipe.name)': \(error.localizedDescription)")
                }
            }

            logger.info("Import completed: \(successCount) successful, \(failureCount) failed")
            return insertedIds
        } catch {
            logger.error("Could not decode MacGourmet file. Error: \(error.localizedDescription)")
            throw ImportError.decodingFailed(error)
        }
    }
}
