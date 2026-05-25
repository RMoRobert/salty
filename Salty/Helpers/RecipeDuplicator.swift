//
//  RecipeDuplicator.swift
//  Salty
//

import Foundation
import SQLiteData
import UUIDV7

enum RecipeDuplicator {
    
    enum DuplicateError: LocalizedError {
        case imageCopyFailed
        
        var errorDescription: String? {
            switch self {
            case .imageCopyFailed:
                return "The recipe was saved but its image could not be copied."
            }
        }
    }
    
    struct Options {
        /// When set and not ~1.0, ingredient lines are scaled with `IngredientScaler`.
        var ingredientScaleFactor: Double? = nil
        var scalePercentLabel: String? = nil
        var sourceRecipeName: String? = nil
    }
    
    /// Inserts a new recipe copied from `source`, with new IDs and a copied image file when present.
    /// - Returns: The new recipe's id.
    @discardableResult
    static func duplicate(
        source: Recipe,
        database: any DatabaseWriter,
        categoryIds: [String],
        tagIds: [String],
        options: Options = Options()
    ) throws -> String {
        let now = Date()
        let newId = UUIDV7().uuidString
        let scaleFactor = options.ingredientScaleFactor
        let isScaling = scaleFactor.map { abs($0 - 1.0) > 0.000_001 } ?? false
        
        var name = source.name
        if isScaling, let label = options.scalePercentLabel {
            name = "\(source.name) (\(label)%)"
        }
        
        var notes = source.notes.map { cloneNote($0) }
        if isScaling,
           let label = options.scalePercentLabel,
           let sourceName = options.sourceRecipeName {
            let scaleNote = Note(
                id: UUIDV7().uuidString,
                title: "Scaled Recipe",
                content: "Ingredients scaled to \(label)% from original recipe, “\(sourceName)”. Directions and other textmay refer to original quantities; please review after scaling."
            )
            notes.insert(scaleNote, at: 0)
        }
        
        var copy = Recipe(
            id: newId,
            name: name,
            createdDate: now,
            lastModifiedDate: now,
            lastPrepared: nil,
            source: source.source,
            sourceDetails: source.sourceDetails,
            introduction: source.introduction,
            difficulty: source.difficulty,
            rating: source.rating,
            imageFilename: nil,
            imageThumbnailData: nil,
            isFavorite: source.isFavorite,
            wantToMake: source.wantToMake,
            yield: source.yield,
            servings: source.servings,
            courseId: source.courseId,
            directions: source.directions.map { cloneDirection($0) },
            ingredients: source.ingredients.map { cloneIngredient($0, scaleFactor: scaleFactor) },
            notes: notes,
            variations: source.variations.map { cloneVariation($0) },
            preparationTimes: source.preparationTimes.map { clonePreparationTime($0) },
            nutrition: source.nutrition
        )
        
        if let filename = source.imageFilename,
           let imageData = RecipeImageManager.shared.loadImage(filename: filename) {
            copy.setImage(imageData)
            if copy.imageFilename == nil {
                throw DuplicateError.imageCopyFailed
            }
        } else if let thumbnailData = source.imageThumbnailData,
                  source.imageFilename == nil {
            // Thumbnail without file is unusual; still attempt to persist if we have bytes only.
            copy.setImage(thumbnailData)
        }
        
        try database.write { db in
            try Recipe.insert(copy).execute(db)
            
            for categoryId in categoryIds {
                let recipeCategory = RecipeCategory(
                    id: UUIDV7().uuidString,
                    recipeId: copy.id,
                    categoryId: categoryId
                )
                try RecipeCategory.insert(recipeCategory).execute(db)
            }
            
            for tagId in tagIds {
                let recipeTag = RecipeTag(
                    id: UUIDV7().uuidString,
                    recipeId: copy.id,
                    tagId: tagId
                )
                try RecipeTag.insert(recipeTag).execute(db)
            }
        }
        
        return copy.id
    }
    
    // MARK: - Private
    
    private static func cloneIngredient(_ ingredient: Ingredient, scaleFactor: Double?) -> Ingredient {
        let text: String
        if ingredient.isHeading {
            text = ingredient.text
        } else if let scaleFactor, abs(scaleFactor - 1.0) > 0.000_001 {
            text = IngredientScaler.scaledText(for: ingredient, scaleFactor: scaleFactor)
        } else {
            text = ingredient.text
        }
        return Ingredient(
            id: UUIDV7().uuidString,
            isHeading: ingredient.isHeading,
            isMain: ingredient.isMain,
            text: text
        )
    }
    
    private static func cloneDirection(_ direction: Direction) -> Direction {
        Direction(
            id: UUIDV7().uuidString,
            isHeading: direction.isHeading,
            text: direction.text
        )
    }
    
    private static func cloneNote(_ note: Note) -> Note {
        Note(id: UUIDV7().uuidString, title: note.title, content: note.content)
    }
    
    private static func cloneVariation(_ variation: Variation) -> Variation {
        Variation(
            id: UUIDV7().uuidString,
            variationName: variation.variationName,
            text: variation.text
        )
    }
    
    private static func clonePreparationTime(_ prepTime: PreparationTime) -> PreparationTime {
        PreparationTime(
            id: UUIDV7().uuidString,
            type: prepTime.type,
            timeString: prepTime.timeString
        )
    }
}
