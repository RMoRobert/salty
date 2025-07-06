//
//  MacGourmetImportHelper.swift
//  Salty
//
//  Created by Robert on 6/1/23.
//

import Foundation
import SharingGRDB

struct MacGourmetImportHelper: ImporterProtocol {
    static func importIntoDatabase(_ database: any DatabaseWriter, xmlFileUrl: URL) async {
        guard let xmlData = getDataFromFile(xmlFileUrl) else {
            print("No XML data; returning")
            return
        }
        
        do {
            let mgRecipes = try PropertyListDecoder().decode([MacGourmetImportRecipe].self, from: xmlData)
            print("Found \(mgRecipes.count) MG recipes")
            
            try await database.write { db in
                for mgRecipe in mgRecipes {
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
                        for categoryName in categories {
                            // Find existing category or create new one
                            var category = try Category.filter(Column("name") == categoryName).fetchOne(db)
                            if category == nil {
                                category = Category(id: UUID().uuidString, name: categoryName)
                                try category!.insert(db)
                            }
                            
                            guard let category = category else { continue }
                            
                            // Create relationship
                            let recipeCategory = RecipeCategory(recipeId: recipe.id, categoryId: category.id)
                            try recipeCategory.insert(db)
                        }
                    }
                }
            }
        } catch {
            print("Could not import. Error: \(error).")
        }
    }
}
