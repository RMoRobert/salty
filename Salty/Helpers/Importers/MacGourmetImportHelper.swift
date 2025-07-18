//
//  MacGourmetImportHelper.swift
//  Salty
//
//  Created by Robert on 6/1/23.
//

import Foundation
import SharingGRDB
import OSLog

struct MacGourmetImportHelper: RecipeFileImporterProtocol {
    private static let logger = Logger(subsystem: "Salty", category: "App")
    
    static func importIntoDatabase(_ database: any DatabaseWriter, xmlFileUrl: URL) async {
        guard let xmlData = getDataFromFile(xmlFileUrl) else {
            logger.error("No XML data found in file; returning")
            return
        }
        
        do {
            let mgRecipes = try PropertyListDecoder().decode([MacGourmetImportRecipe].self, from: xmlData)
            logger.info("Found \(mgRecipes.count) MG recipes to import")
            
            var successCount = 0
            var failureCount = 0
            
            for mgRecipe in mgRecipes {
                do {
                    try await database.write { db in
                        var imgData: Data?
                        var categories: [String]?
                        var recipe = mgRecipe.convertToRecipe(imageData: &imgData, categories: &categories)
                        
                        // Save the recipe
                        try recipe.insert(db)
                        
                        // Save image if present (this needs to happen after recipe is saved)
                        if let imgData = imgData {
                            recipe.setImage(imgData)
                            // Update the recipe in database with image info
                            try recipe.update(db)
                        }
                        
                        // Save categories if present
                        if let categories = categories {
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
                                    let recipeCategory = RecipeCategory(recipeId: recipe.id, categoryId: category.id)
                                    try recipeCategory.insert(db)
                                }
                            }
                        }
                        
                        // Set course if present
                        if let courseName = mgRecipe.courseName, !courseName.isEmpty, courseName != "--" {
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
                    logger.error("Failed to import recipe '\(mgRecipe.name)': \(error.localizedDescription)")
                }
            }
            
            logger.info("Import completed: \(successCount) successful, \(failureCount) failed")
        } catch {
            logger.error("Could not decode MacGourmet file. Error: \(error.localizedDescription)")
        }
    }
}
