//
//  SaltyRecipeExport.swift
//  Salty
//
//  Created by Robert on 8/16/25.
//

import Foundation
import SQLiteData
import UniformTypeIdentifiers

extension UTType {
    static let saltyRecipe = UTType(exportedAs: "com.inuvro.salty.recipe")
    static let saltyRecipeLibrary = UTType(exportedAs: "com.inuvro.salty.recipeLibrary")
}

        FileRepresentation(contentType: .saltyRecipe) { recipe in
// MARK: - Export-Optimized Structs

/// Optimized Direction struct for export/import - removes internal IDs and makes optional fields truly optional
struct SaltyDirectionExport: Codable, Equatable {
    var text: String
    var isHeading: Bool?
    
    init(from direction: Direction) {
        self.text = direction.text
        self.isHeading = direction.isHeading
    }
    
    func convertToDirection() -> Direction {
        return Direction(
            id: UUID().uuidString,
            isHeading: isHeading,
            text: text
        )
    }
}

/// Optimized Ingredient struct for export/import - removes internal IDs and makes optional fields truly optional
struct SaltyIngredientExport: Codable, Equatable {
    var text: String
    var isHeading: Bool?
    var isMain: Bool?
    
    init(from ingredient: Ingredient) {
        self.text = ingredient.text
        self.isHeading = ingredient.isHeading ? true : nil
        self.isMain = ingredient.isMain ? true : nil
    }
    
    func convertToIngredient() -> Ingredient {
        return Ingredient(
            id: UUID().uuidString,
            isHeading: isHeading ?? false,
            isMain: isMain ?? false,
            text: text
        )
    }
}

/// Optimized PreparationTime struct for export/import - removes internal IDs
struct SaltyPreparationTimeExport: Codable, Equatable {
    var type: String
    var timeString: String
    
    init(from prepTime: PreparationTime) {
        self.type = prepTime.type
        self.timeString = prepTime.timeString
    }
    
    func convertToPreparationTime() -> PreparationTime {
        return PreparationTime(
            id: UUID().uuidString,
            type: type,
            timeString: timeString
        )
    }
}


/// A Recipe-like object generally suitable for export, sharing, and ease of later import via similar importer object. Small
/// differences from `Recipe` exist, e.g., most properties optional (and may be excluded from export if not provided);
/// image data stored directly instead of via filename; and category, course, and tags provided by name and not ID references
struct SaltyRecipeExport: Codable, Equatable {
    var version: String = "1.0"  // not sure if we'll need this, but should help with future-proofing if major changes are needed
    var id: String
    var name: String
    var createdDate: Date?
    var lastModifiedDate: Date?
    var lastPrepared: Date?
    var source: String?
    var sourceDetails: String?
    var introduction: String?
    var difficulty: Difficulty = .notSet
    var rating: Rating = .notSet
    var imageData: Data?  // differs from imageFilename in Recipe
    var isFavorite: Bool = false
    var wantToMake: Bool = false
    var yield: String?
    var servings: Int?
    var course: String? // differs from courseId in Recipe
    var categories: [String]? // doing as name here instead of via join table
    var tags: [String]? // also doing as name here instead of via join table
    var directions: [SaltyDirectionExport] = []
    var ingredients: [SaltyIngredientExport] = []
    var notes: [Note] = []
    var preparationTimes: [SaltyPreparationTimeExport] = []
    var nutrition: NutritionInformation?
}

extension SaltyRecipeExport {
    
    /// Creates a SaltyRecipeExport from a Recipe, fetching related data from the database
    /// - Parameters:
    ///   - recipe: The Recipe to convert
    ///   - database: The database to fetch related data from
    /// - Returns: A SaltyRecipeExport with all data populated
    static func fromRecipe(_ recipe: Recipe, database: any DatabaseWriter) throws -> SaltyRecipeExport {
        // Fetch course name if courseId exists
        var courseName: String?
        if let courseId = recipe.courseId {
            courseName = try database.read { db in
                try Course
                    .where { $0.id == courseId }
                    .fetchOne(db)?.name
            }
        }
        
        // Fetch category names
        let categoryNames = try database.read { db in
            let recipeCategoryIds = try RecipeCategory
                .where { $0.recipeId == recipe.id }
                .fetchAll(db)
                .map { $0.categoryId }
            
            return try Category
                .where { recipeCategoryIds.contains($0.id) }
                .fetchAll(db)
                .map { $0.name }
                .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        }
        
        // Fetch tag names
        let tagNames = try database.read { db in
            let recipeTagIds = try RecipeTag
                .where { $0.recipeId == recipe.id }
                .fetchAll(db)
                .map { $0.tagId }
            
            return try Tag
                .where { recipeTagIds.contains($0.id) }
                .fetchAll(db)
                .map { $0.name }
                .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
        }
        
        // Fetch full image data if imageFilename exists
        var imageData: Data?
        if let imageFilename = recipe.imageFilename {
            imageData = RecipeImageManager.shared.loadImage(filename: imageFilename)
        }
        
        return SaltyRecipeExport(
            id: recipe.id,
            name: recipe.name,
            createdDate: recipe.createdDate,
            lastModifiedDate: recipe.lastModifiedDate,
            lastPrepared: recipe.lastPrepared,
            source: recipe.source.isEmpty ? nil : recipe.source,
            sourceDetails: recipe.sourceDetails.isEmpty ? nil : recipe.sourceDetails,
            introduction: recipe.introduction.isEmpty ? nil : recipe.introduction,
            difficulty: recipe.difficulty,
            rating: recipe.rating,
            imageData: imageData,
            isFavorite: recipe.isFavorite,
            wantToMake: recipe.wantToMake,
            yield: recipe.yield.isEmpty ? nil : recipe.yield,
            servings: recipe.servings,
            course: courseName,
            categories: categoryNames.isEmpty ? nil : categoryNames,
            tags: tagNames.isEmpty ? nil : tagNames,
            directions: recipe.directions.map { SaltyDirectionExport(from: $0) },
            ingredients: recipe.ingredients.map { SaltyIngredientExport(from: $0) },
            notes: recipe.notes,
            preparationTimes: recipe.preparationTimes.map { SaltyPreparationTimeExport(from: $0) },
            nutrition: recipe.nutrition
        )
    }
    
    /// Exports the recipe to JSON data
    /// - Returns: JSON data representation of the recipe
    func toJSONData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
    
    /// Exports the recipe to a JSON string
    /// - Returns: JSON string representation of the recipe
    func toJSONString() throws -> String {
        let data = try toJSONData()
        guard let string = String(data: data, encoding: .utf8) else {
            throw EncodingError.invalidValue(self, EncodingError.Context(
                codingPath: [],
                debugDescription: "Failed to convert JSON data to string"
            ))
        }
        return string
    }
    
    /// Converts SaltyRecipeExport to Recipe object
    /// - Returns: Recipe object with matching data from the SaltyRecipeExport
    func convertToRecipe() -> Recipe {
        var recipe = Recipe(
            id: UUID().uuidString, // Generate new ID for import
            name: name,
            createdDate: createdDate ?? Date(),
            lastModifiedDate: lastModifiedDate ?? Date(),
            lastPrepared: lastPrepared,
            source: source ?? "",
            sourceDetails: sourceDetails ?? "",
            introduction: introduction ?? "",
            difficulty: difficulty,
            rating: rating,
            imageFilename: nil, // Will be set after image is saved
            imageThumbnailData: nil, // Will be set after image is saved
            isFavorite: isFavorite,
            wantToMake: wantToMake,
            yield: yield ?? "",
            servings: servings,
            courseId: nil, // Will be set after course is resolved
            directions: directions.map { $0.convertToDirection() },
            ingredients: ingredients.map { $0.convertToIngredient() },
            notes: notes,
            preparationTimes: preparationTimes.map { $0.convertToPreparationTime() },
            nutrition: nutrition
        )
        
        return recipe
    }
}
