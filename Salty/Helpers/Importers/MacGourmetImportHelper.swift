//
//  MacGourmetImportHelper.swift
//  Salty
//
//  Created by Robert on 6/1/23.
//

import Foundation
import RealmSwift

struct MacGourmetImportHelper: ImporterProtocol {
    static func importIntoRecipeLibrary(_ recipeLibrary: RecipeLibrary, xmlFileUrl: URL) -> () {
        guard let xmlData = getDataFromFile(xmlFileUrl) else {
            return
        }
        
        do {
            let mgRecipes = try PropertyListDecoder().decode([MacGourmetImportRecipe].self, from: xmlData)
            mgRecipes.forEach { mgRecipe in
                var imgData: Data?
                var categories: [String]?
                let recipe = mgRecipe.convertToRecipe(imageData: &imgData, categories: &categories)
               
                
                do {
                    let realm = recipeLibrary.realm!.thaw()
                    let thawedRecipeLibrary = recipeLibrary.thaw()!
                    try realm.write {
                        thawedRecipeLibrary.recipes.append(recipe)
                    }
                }
                catch {
                    print("Error saving appending recipe: \(error)")
                    return
                }
                
                if let imgData = imgData {
                    recipe.saveImageForRecipe(imageData: imgData)
                }
                
                if let categories = categories {
                    categories.forEach { category in
                        recipe.addCategoryByName(category)
                    }
                }
            }
        }
        catch {
            print("Could not import. Error: \(error).")
        }
        
    }
}
