//
//  Recipe.swift
//  Salty
//
//  Created by Robert on 4/19/23.
//

import Foundation
import RealmSwift

final class Recipe: EmbeddedObject, ObjectKeyIdentifiable {
    //@Persisted(primaryKey: true) var _id: ObjectId
    @Persisted var _id: ObjectId
    /// The backlink to the `RecipeLibrary` this item is a part of.
    @Persisted(originProperty: "recipes") var recipeLibrary: LinkingObjects<RecipeLibrary>
    @Persisted var name: String = "New Recipe"
    @Persisted var source = ""
    @Persisted var sourceDetails = ""
    @Persisted var introduction = ""
    @Persisted var difficulty: Difficulty = .notSet
    @Persisted var rating: Rating = .notSet
    @Persisted var imageName: String? // store relative path
    @Persisted var prepared = false
    @Persisted var isFavorite = false
    @Persisted var wantToMake = false
    @Persisted var yield = ""
    @Persisted var directions = List<Direction>()
    @Persisted var ingredients = List<Ingredient>()
    @Persisted var notes = List<Note>()
    @Persisted var preparationTimes = List<PreparationTime>()
    @Persisted var categories = List<Category>()
    
    enum Difficulty: Int, PersistableEnum, CaseIterable {
        case notSet, easy, somewhatEasy, medium, slightlyDifficult, difficult
        
        // for use with SwiftUI sliders:
        init(index: Double = 0) {
            if let type = Self.allCases.first(where: { $0.asIndex == index }) {
                self = type
            } else {
                self = .notSet
            }
        }
        var asIndex: Double {
            return Double(self.rawValue)
        }
        
        func stringValue() -> String {
            switch(self) {
            case .notSet:
                return "(not set)"
            case .easy:
                return "easy"
            case .somewhatEasy:
                return "somewhat easy"
            case .medium:
                return "medium"
            case .slightlyDifficult:
                return "slightly difficult"
            case .difficult:
                return "difficult"
            }
        }
    }
    
    enum Rating: Int, PersistableEnum, CaseIterable {
        case notSet, one, two, three, four, five
        
        // for use with SwiftUI sliders:
        init(index: Double = 0) {
            if let type = Self.allCases.first(where: { $0.asIndex == index }) {
                self = type
            } else {
                self = .notSet
            }
        }
        var asIndex: Double {
            return Double(self.rawValue)
        }
        
        func stringValue() -> String {
            switch(self) {
            case .notSet:
                return "not set"
            case .one:
                return "1"
            case .two:
                return "2"
            case .three:
                return "3"
            case .four:
                return "4"
            case .five:
                return "5"
            }
        }
    }
}


extension Recipe {
    /// Add category to recipe by name; creates category with name if does not exist, otherwises uses existing category.
    func addCategoryByName(_ name: String) -> () {
        let matchingCategories = recipeLibrary.first?.categories.where {
            ($0.name == name)
        }
        if let theCategory = matchingCategories?.first {
            if let _ = recipeLibrary.first?.categories.realm?.thaw() {
                try? realm!.write {
                    categories.append(theCategory)
                }
            }
        }
        else {
            if let thawedRecipeLibrary = recipeLibrary.thaw() {
                try? realm!.write {
                    let newCategory = Category()
                    newCategory.name = name
                    thawedRecipeLibrary.first?.categories.append(newCategory)
                    categories.append(newCategory)
                }
            }
        }
    }
    
}
