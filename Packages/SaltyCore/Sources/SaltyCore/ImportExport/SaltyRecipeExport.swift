//
//  SaltyRecipeExport.swift
//  Salty
//
//  Created by Robert on 8/16/25.
//

import Foundation
import SQLiteData
import UniformTypeIdentifiers
import CoreTransferable
import UUIDV7

public extension UTType {
    public static let saltyRecipe = UTType(exportedAs: "com.inuvro.salty.recipe", conformingTo:  .json)
    public static let saltyRecipeLibrary = UTType(exportedAs: "com.inuvro.salty.recipeLibrary")
}

extension SaltyRecipeExport: Transferable {
    public static var transferRepresentation: some TransferRepresentation {
        // A real .saltyRecipe file is the representation that AirDrops cleanly and lets the receiving
        // device "Open in Salty" (the app registers this UTType in Info.plist). A FileRepresentation is
        // far more reliable for this than CodableRepresentation, which historically failed to populate
        // some share destinations. Plain text is kept as a fallback for Mail/Messages to recipients
        // who don't have Salty.
        FileRepresentation(contentType: .saltyRecipe) { recipe in
            let safeName = recipe.name
                .replacingOccurrences(of: "/", with: "-")
                .replacingOccurrences(of: ":", with: "-")
                .trimmingCharacters(in: .whitespacesAndNewlines)
            let filename = safeName.isEmpty ? "Recipe" : safeName
            let url = URL.temporaryDirectory.appendingPathComponent(filename, conformingTo: .saltyRecipe)
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601  // match SaltyRecipeImportHelper's decoder
            try encoder.encode(recipe).write(to: url, options: .atomic)
            return SentTransferredFile(url)
        } importing: { received in
            let decoder = JSONDecoder()
            decoder.dateDecodingStrategy = .iso8601
            return try decoder.decode(SaltyRecipeExport.self, from: Data(contentsOf: received.file))
        }

        // Fallback: readable plain text for Mail/Messages to recipients without Salty.
        DataRepresentation(contentType: .plainText) { recipe in
            let text = recipe.plainTextRepresentation
            return text.data(using: .utf8) ?? Data()
        } importing: { data in
            // This probably won't work super-well, but is required and should do *something*:
            let recipe: Recipe = RecipeFromTextParser().parseRecipe(from: String(data: data, encoding: .utf8) ?? "")
            return try self.fromRecipe(recipe)
        }
    }
}

// MARK: - Export-Optimized Structs

/// Optimized Direction struct for export/import - removes internal IDs and makes optional fields truly optional
public struct SaltyDirectionExport: Codable, Equatable {
    public var text: String
    public var isHeading: Bool?
    
    public init(from direction: Direction) {
        self.text = direction.text
        self.isHeading = direction.isHeading
    }
    
    public func convertToDirection() -> Direction {
        return Direction(
            id: UUIDV7().uuidString,
            isHeading: isHeading,
            text: text
        )
    }
}

/// Optimized Ingredient struct for export/import - removes internal IDs and makes optional fields truly optional
public struct SaltyIngredientExport: Codable, Equatable {
    public var text: String
    public var isHeading: Bool?
    public var isMain: Bool?
    
    public init(from ingredient: Ingredient) {
        self.text = ingredient.text
        self.isHeading = ingredient.isHeading ? true : nil
        self.isMain = ingredient.isMain ? true : nil
    }
    
    public func convertToIngredient() -> Ingredient {
        return Ingredient(
            id: UUIDV7().uuidString,
            isHeading: isHeading ?? false,
            isMain: isMain ?? false,
            text: text
        )
    }
}

/// Optimized PreparationTime struct for export/import - removes internal IDs
public struct SaltyPreparationTimeExport: Codable, Equatable {
    public var type: String
    public var timeString: String
    
    public init(from prepTime: PreparationTime) {
        self.type = prepTime.type
        self.timeString = prepTime.timeString
    }
    
    public func convertToPreparationTime() -> PreparationTime {
        return PreparationTime(
            id: UUIDV7().uuidString,
            type: type,
            timeString: timeString
        )
    }
}

/// Optimized Variation struct for export/import - removes internal IDs
public struct SaltyVariationExport: Codable, Equatable {
    public var variationName: String
    public var text: String
    
    public init(from variation: Variation) {
        self.variationName = variation.variationName
        self.text = variation.text
    }
    
    public func convertToVariation() -> Variation {
        return Variation(
            id: UUIDV7().uuidString,
            variationName: variationName,
            text: text
        )
    }
}


/// A Recipe-like object generally suitable for export, sharing, and ease of later import via similar importer object. Small
/// differences from `Recipe` exist, e.g., most properties optional (and may be excluded from export if not provided);
/// image data stored directly instead of via filename; and category, course, and tags provided by name and not ID references
public struct SaltyRecipeExport: Codable, Equatable {
    public var version: String = "1.0"  // not sure if we'll need this, but should help with future-proofing if major changes are needed
    public var id: String
    public var name: String
    public var createdDate: Date?
    public var lastModifiedDate: Date?
    public var lastPrepared: Date?
    public var source: String?
    public var sourceDetails: String?
    public var introduction: String?
    public var difficulty: Difficulty = .notSet
    public var rating: Rating = .notSet
    public var imageData: Data?  // differs from imageFilename in Recipe
    public var isFavorite: Bool = false
    public var wantToMake: Bool = false
    public var yield: String?
    public var servings: Int?
    public var course: String? // differs from courseId in Recipe
    public var categories: [String]? // doing as name here instead of via join table
    public var tags: [String]? // also doing as name here instead of via join table
    public var directions: [SaltyDirectionExport] = []
    public var ingredients: [SaltyIngredientExport] = []
    public var notes: [Note] = []
    public var variations: [SaltyVariationExport]? // Optional for backwards compatibility
    public var preparationTimes: [SaltyPreparationTimeExport] = []
    public var nutrition: NutritionInformation?

    public init(
        version: String = "1.0",
        id: String,
        name: String,
        createdDate: Date? = nil,
        lastModifiedDate: Date? = nil,
        lastPrepared: Date? = nil,
        source: String? = nil,
        sourceDetails: String? = nil,
        introduction: String? = nil,
        difficulty: Difficulty = .notSet,
        rating: Rating = .notSet,
        imageData: Data? = nil,
        isFavorite: Bool = false,
        wantToMake: Bool = false,
        yield: String? = nil,
        servings: Int? = nil,
        course: String? = nil,
        categories: [String]? = nil,
        tags: [String]? = nil,
        directions: [SaltyDirectionExport] = [],
        ingredients: [SaltyIngredientExport] = [],
        notes: [Note] = [],
        variations: [SaltyVariationExport]? = nil,
        preparationTimes: [SaltyPreparationTimeExport] = [],
        nutrition: NutritionInformation? = nil
    ) {
        self.version = version
        self.id = id
        self.name = name
        self.createdDate = createdDate
        self.lastModifiedDate = lastModifiedDate
        self.lastPrepared = lastPrepared
        self.source = source
        self.sourceDetails = sourceDetails
        self.introduction = introduction
        self.difficulty = difficulty
        self.rating = rating
        self.imageData = imageData
        self.isFavorite = isFavorite
        self.wantToMake = wantToMake
        self.yield = yield
        self.servings = servings
        self.course = course
        self.categories = categories
        self.tags = tags
        self.directions = directions
        self.ingredients = ingredients
        self.notes = notes
        self.variations = variations
        self.preparationTimes = preparationTimes
        self.nutrition = nutrition
    }
}

public extension SaltyRecipeExport {
    
    /// Creates a SaltyRecipeExport from a Recipe, fetching related data from the database
    /// - Parameters:
    ///   - recipe: The Recipe to convert
    ///   - database: The database to fetch related data from
    ///   - imageData: The recipe's full image bytes, or nil. Passed in rather than loaded here because
    ///     images live in an app-owned folder that SaltyCore knows nothing about; the app's
    ///     `fromRecipe(_:database:)` overload supplies it from `Recipe.fullImageData`.
    /// - Returns: A SaltyRecipeExport with all data populated
    public static func fromRecipe(
        _ recipe: Recipe,
        database: any DatabaseWriter,
        imageData: Data?
    ) throws -> SaltyRecipeExport {
        // Fetch course name if courseId exists
        var courseName: String?
        if let courseId = recipe.courseId {
            courseName = try database.read { db in
                try Course
                    .where { $0.id.eq(courseId) }
                    .fetchOne(db)?.name
            }
        }
        
        // Fetch category names
        let categoryNames = try database.read { db in
            let recipeCategoryIds = try RecipeCategory
                .where { $0.recipeId.eq(recipe.id) }
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
                .where { $0.recipeId.eq(recipe.id) }
                .fetchAll(db)
                .map { $0.tagId }
            
            return try Tag
                .where { recipeTagIds.contains($0.id) }
                .fetchAll(db)
                .map { $0.name }
                .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
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
            variations: recipe.variations.isEmpty ? nil : recipe.variations.map { SaltyVariationExport(from: $0) },
            preparationTimes: recipe.preparationTimes.map { SaltyPreparationTimeExport(from: $0) },
            nutrition: recipe.nutrition
        )
    }
    
    /// Creates a SaltyRecipeExport from a Recipe with no attempts to fetch any database information (course, categories, etc.)
    /// - Parameters:
    ///   - recipe: The Recipe to convert
    /// - Returns: A SaltyRecipeExport with all data populated
    public static func fromRecipe(_ recipe: Recipe) throws -> SaltyRecipeExport {
        
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
            isFavorite: recipe.isFavorite,
            wantToMake: recipe.wantToMake,
            yield: recipe.yield.isEmpty ? nil : recipe.yield,
            servings: recipe.servings,
            directions: recipe.directions.map { SaltyDirectionExport(from: $0) },
            ingredients: recipe.ingredients.map { SaltyIngredientExport(from: $0) },
            notes: recipe.notes,
            variations: recipe.variations.isEmpty ? nil : recipe.variations.map { SaltyVariationExport(from: $0) },
            preparationTimes: recipe.preparationTimes.map { SaltyPreparationTimeExport(from: $0) },
            nutrition: recipe.nutrition
        )
    }
    
    /// Plain text representation of the recipe for text-only transfer operations like text messaging, etc.
    public var plainTextRepresentation: String {
        var text = ""
        
        // Recipe name
        text += "\(name)\n"
        text += String(repeating: "=", count: name.count) + "\n\n"
        
        // Source information
        if let source = source, !source.isEmpty {
            text += "Source: \(source)\n"
        }
        if let sourceDetails = sourceDetails, !sourceDetails.isEmpty {
            text += "Source Details: \(sourceDetails)\n"
        }
        
        // Yield and servings
        if let yield = yield, !yield.isEmpty {
            text += "Yield: \(yield)\n"
        }
        if let servings = servings {
            text += "Servings: \(servings)\n"
        }
        
        // Introduction
        if let introduction = introduction, !introduction.isEmpty {
            text += "\n\(introduction)\n"
        }
        
        // Preparation times
        if !preparationTimes.isEmpty {
            text += "\nPreparation Times:\n"
            for prepTime in preparationTimes {
                text += "• \(prepTime.type): \(prepTime.timeString)\n"
            }
        }
        
        // Ingredients
        if !ingredients.isEmpty {
            text += "\nIngredients:\n"
            for ingredient in ingredients {
                if ingredient.isHeading == true {
                    text += "\n\(ingredient.text)\n"
                } else {
                    text += "• \(ingredient.text)\n"
                }
            }
        }
        
        // Directions
        if !directions.isEmpty {
            text += "\nDirections:\n"
            for (index, direction) in directions.enumerated() {
                if direction.isHeading == true {
                    text += "\n\(direction.text)\n"
                } else {
                    text += "\(index + 1). \(direction.text)\n"
                }
            }
        }
        
        // Notes
        if !notes.isEmpty {
            text += "\nNotes:\n"
            for note in notes {
                text += "• \(note.title): \(note.content)\n"
            }
        }
        
        // Variations
        if let variations = variations, !variations.isEmpty {
            text += "\nVariations:\n"
            for variation in variations {
                if !variation.variationName.isEmpty {
                    text += "• \(variation.variationName): \(variation.text)\n"
                } else {
                    text += "• \(variation.text)\n"
                }
            }
        }
        
        return text
    }
    
    /// Exports the recipe to JSON data
    /// - Returns: JSON data representation of the recipe
    public func toJSONData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return try encoder.encode(self)
    }
    
    /// Exports the recipe to a JSON string
    /// - Returns: JSON string representation of the recipe
    public func toJSONString() throws -> String {
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
    public func convertToRecipe() -> Recipe {
        let recipe = Recipe(
            id: UUIDV7().uuidString, // Generate new ID for import
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
            notes: notes.map { Note(id: UUIDV7().uuidString, title: $0.title, content: $0.content) },
            variations: variations?.map { $0.convertToVariation() } ?? [],
            preparationTimes: preparationTimes.map { $0.convertToPreparationTime() },
            nutrition: nutrition
        )
        
        return recipe
    }
}
