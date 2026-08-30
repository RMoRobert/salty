//
//  ServerRecipe.swift
//  SaltyCore
//
//  The recipe wire shape and its nested payloads, plus the conversions to and from the local model.
//  Mirrors SaltyKMP's equivalents; a field added here needs adding there too.
//

import Foundation
import UUIDV7

public struct ServerRecipe: Codable, Sendable {
    public var id: String
    public var name: String
    public var createdDate: Date?
    public var lastModifiedDate: Date?
    public var lastPrepared: Date?
    // Bumped only when lastPrepared changes; the server merges the pair by this stamp on every upsert,
    // so the two must always travel together (see RecipeRepository.upsert in salty_kmp).
    public var lastModifiedPreparedDate: Date?
    public var source: String?
    public var sourceDetails: String?
    public var introduction: String?
    public var difficulty: Int?
    public var rating: Int?
    public var imageFilename: String?
    public var lastModifiedImageDate: Date?
    public var isFavorite: Bool?
    public var wantToMake: Bool?
    public var yield: String?
    public var servings: Int?
    public var courseId: String?  // Using course.id from server
    public var directions: [ServerDirection]?
    public var ingredients: [ServerIngredient]?
    public var notes: [ServerNote]?
    public var variations: [ServerVariation]?
    public var preparationTimes: [ServerPreparationTime]?
    public var nutrition: ServerNutrition?
    
    // Server sends course as nested object, we need to extract ID
    public var course: ServerCourse?
    
    // Category and tag relationships
    public var categoryIds: [String]?
    public var tagIds: [String]?
    
    enum CodingKeys: String, CodingKey {
        case id, name, createdDate, lastModifiedDate, lastPrepared, lastModifiedPreparedDate
        case source, sourceDetails, introduction
        case difficulty, rating, imageFilename, lastModifiedImageDate
        case isFavorite, wantToMake, yield, servings
        case courseId, course
        case directions, ingredients, notes, variations
        case preparationTimes, nutrition
        case categoryIds, tagIds
    }
    
    public static func from(_ recipe: Recipe) -> ServerRecipe {
        return ServerRecipe(
            id: recipe.id,
            name: recipe.name,
            createdDate: recipe.createdDate,
            lastModifiedDate: recipe.lastModifiedDate,
            lastPrepared: recipe.lastPrepared,
            lastModifiedPreparedDate: recipe.lastModifiedPreparedDate,
            source: recipe.source,
            sourceDetails: recipe.sourceDetails,
            introduction: recipe.introduction,
            difficulty: recipe.difficulty.rawValue,
            rating: recipe.rating.rawValue,
            imageFilename: recipe.imageFilename,
            lastModifiedImageDate: recipe.lastModifiedImageDate,
            isFavorite: recipe.isFavorite,
            wantToMake: recipe.wantToMake,
            yield: recipe.yield,
            servings: recipe.servings,
            courseId: recipe.courseId,
            directions: recipe.directions.map { ServerDirection.from($0) },
            ingredients: recipe.ingredients.map { ServerIngredient.from($0) },
            notes: recipe.notes.map { ServerNote.from($0) },
            variations: recipe.variations.map { ServerVariation.from($0) },
            preparationTimes: recipe.preparationTimes.map { ServerPreparationTime.from($0) },
            nutrition: recipe.nutrition.map { ServerNutrition.from($0) }
        )
    }
    
    public func toLocalRecipe() -> Recipe {
        return Recipe(
            id: id,
            name: name,
            createdDate: createdDate ?? Date(),
            lastModifiedDate: lastModifiedDate ?? Date(),
            lastPrepared: lastPrepared,
            lastModifiedPreparedDate: lastModifiedPreparedDate,
            source: source ?? "",
            sourceDetails: sourceDetails ?? "",
            introduction: introduction ?? "",
            difficulty: Difficulty(rawValue: difficulty ?? 0) ?? .notSet,
            rating: Rating(rawValue: rating ?? 0) ?? .notSet,
            imageFilename: imageFilename,
            imageThumbnailData: nil, // Will be set when image is downloaded
            lastModifiedImageDate: lastModifiedImageDate,
            isFavorite: isFavorite ?? false,
            wantToMake: wantToMake ?? false,
            yield: yield ?? "",
            servings: servings,
            courseId: course?.id ?? courseId,
            directions: directions?.map { $0.toLocal() } ?? [],
            ingredients: ingredients?.map { $0.toLocal() } ?? [],
            notes: notes?.map { $0.toLocal() } ?? [],
            variations: variations?.map { $0.toLocal() } ?? [],
            preparationTimes: preparationTimes?.map { $0.toLocal() } ?? [],
            nutrition: nutrition?.toLocal()
        )
    }
}

public struct ServerDirection: Codable, Sendable {
    public var id: String
    public var isHeading: Bool?
    public var text: String
    
    public static func from(_ direction: Direction) -> ServerDirection {
        ServerDirection(id: direction.id, isHeading: direction.isHeading, text: direction.text)
    }
    
    public func toLocal() -> Direction {
        Direction(id: id, isHeading: isHeading, text: text)
    }
}

public struct ServerIngredient: Codable, Sendable {
    public var id: String
    public var isHeading: Bool?
    public var isMain: Bool?
    public var text: String
    
    public static func from(_ ingredient: Ingredient) -> ServerIngredient {
        ServerIngredient(id: ingredient.id, isHeading: ingredient.isHeading, isMain: ingredient.isMain, text: ingredient.text)
    }
    
    public func toLocal() -> Ingredient {
        Ingredient(id: id, isHeading: isHeading ?? false, isMain: isMain ?? false, text: text)
    }
}

public struct ServerNote: Codable, Sendable {
    public var id: String
    public var title: String?
    public var content: String?
    public var text: String?  // Server might use 'text' instead of 'content'
    
    public static func from(_ note: Note) -> ServerNote {
        ServerNote(id: note.id, title: note.title, content: note.content, text: nil)
    }
    
    public func toLocal() -> Note {
        Note(id: id, title: title ?? "", content: content ?? text ?? "")
    }
}

public struct ServerVariation: Codable, Sendable {
    public var id: String
    public var variationName: String?
    public var text: String
    
    public static func from(_ variation: Variation) -> ServerVariation {
        ServerVariation(id: variation.id, variationName: variation.variationName, text: variation.text)
    }
    
    public func toLocal() -> Variation {
        Variation(id: id, variationName: variationName ?? "", text: text)
    }
}

public struct ServerPreparationTime: Codable, Sendable {
    public var id: String
    public var type: String
    public var timeString: String
    
    public static func from(_ prepTime: PreparationTime) -> ServerPreparationTime {
        ServerPreparationTime(id: prepTime.id, type: prepTime.type, timeString: prepTime.timeString)
    }
    
    public func toLocal() -> PreparationTime {
        PreparationTime(id: id, type: type, timeString: timeString)
    }
}

public struct ServerNutrition: Codable, Sendable {
    public var id: String?
    public var servingSize: String?
    public var calories: Double?
    public var protein: Double?
    public var carbohydrates: Double?
    public var fat: Double?
    public var saturatedFat: Double?
    public var transFat: Double?
    public var fiber: Double?
    public var sugar: Double?
    public var sodium: Double?
    public var cholesterol: Double?
    public var addedSugar: Double?
    public var vitaminD: Double?
    public var calcium: Double?
    public var iron: Double?
    public var potassium: Double?
    public var vitaminA: Double?
    public var vitaminC: Double?
    
    public static func from(_ nutrition: NutritionInformation) -> ServerNutrition {
        ServerNutrition(
            id: nutrition.id,
            servingSize: nutrition.servingSize,
            calories: nutrition.calories,
            protein: nutrition.protein,
            carbohydrates: nutrition.carbohydrates,
            fat: nutrition.fat,
            saturatedFat: nutrition.saturatedFat,
            transFat: nutrition.transFat,
            fiber: nutrition.fiber,
            sugar: nutrition.sugar,
            sodium: nutrition.sodium,
            cholesterol: nutrition.cholesterol,
            addedSugar: nutrition.addedSugar,
            vitaminD: nutrition.vitaminD,
            calcium: nutrition.calcium,
            iron: nutrition.iron,
            potassium: nutrition.potassium,
            vitaminA: nutrition.vitaminA,
            vitaminC: nutrition.vitaminC
        )
    }
    
    public func toLocal() -> NutritionInformation {
        NutritionInformation(
            id: id ?? UUIDV7().uuidString,
            servingSize: servingSize,
            calories: calories,
            protein: protein,
            carbohydrates: carbohydrates,
            fat: fat,
            saturatedFat: saturatedFat,
            transFat: transFat,
            fiber: fiber,
            sugar: sugar,
            sodium: sodium,
            cholesterol: cholesterol,
            addedSugar: addedSugar,
            vitaminD: vitaminD,
            calcium: calcium,
            iron: iron,
            potassium: potassium,
            vitaminA: vitaminA,
            vitaminC: vitaminC
        )
    }
}
