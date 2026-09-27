//
//  SaltyRecipeExport+Decoding.swift
//  SaltyCore
//
//  Reading a `.saltyRecipe` recipe as forgivingly as the format allows.
//
//  The synthesized decoder requires every non-optional key, so hand-written or older files missing
//  e.g. `version` or `notes` would fail. Only `name` is required; a missing `id` gets a fresh one
//  (import mints new ids anyway), missing flags and lists take defaults, and an unreadable date,
//  rating or difficulty is left unset. Matches Salty.NET's reader. Encoding is unchanged.
//

import Foundation
import UUIDV7

extension SaltyRecipeExport {

    private enum LenientKeys: String, CodingKey {
        case version, id, name, createdDate, lastModifiedDate, lastPrepared, source, sourceDetails
        case introduction, difficulty, rating, imageData, isFavorite, wantToMake, yield, servings
        case course, categories, tags, directions, ingredients, notes, variations, preparationTimes
        case nutrition
    }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: LenientKeys.self)
        guard let name = try c.decodeIfPresent(String.self, forKey: .name) else {
            throw DecodingError.keyNotFound(
                LenientKeys.name, .init(codingPath: c.codingPath, debugDescription: "A recipe needs a name."))
        }

        func optional<T: Decodable>(_ type: T.Type, _ key: LenientKeys) -> T? {
            (try? c.decodeIfPresent(type, forKey: key)) ?? nil
        }

        self.init(
            version: optional(String.self, .version) ?? "1.0",
            id: optional(String.self, .id) ?? UUIDV7().uuidString,
            name: name,
            createdDate: optional(Date.self, .createdDate),
            lastModifiedDate: optional(Date.self, .lastModifiedDate),
            lastPrepared: optional(Date.self, .lastPrepared),
            source: optional(String.self, .source),
            sourceDetails: optional(String.self, .sourceDetails),
            introduction: optional(String.self, .introduction),
            difficulty: optional(Int.self, .difficulty).flatMap(Difficulty.init(rawValue:)) ?? .notSet,
            rating: optional(Int.self, .rating).flatMap(Rating.init(rawValue:)) ?? .notSet,
            imageData: optional(Data.self, .imageData),
            isFavorite: optional(Bool.self, .isFavorite) ?? false,
            wantToMake: optional(Bool.self, .wantToMake) ?? false,
            yield: optional(String.self, .yield),
            servings: optional(Int.self, .servings),
            course: optional(String.self, .course),
            categories: optional([String].self, .categories),
            tags: optional([String].self, .tags),
            // The lists are decoded whole, not item by item: an entry missing its text is a damaged
            // file, and quietly dropping ingredients from someone's recipe is worse than refusing it.
            directions: try c.decodeIfPresent([SaltyDirectionExport].self, forKey: .directions) ?? [],
            ingredients: try c.decodeIfPresent([SaltyIngredientExport].self, forKey: .ingredients) ?? [],
            notes: try c.decodeIfPresent([Note].self, forKey: .notes) ?? [],
            variations: try c.decodeIfPresent([SaltyVariationExport].self, forKey: .variations),
            preparationTimes: try c.decodeIfPresent([SaltyPreparationTimeExport].self, forKey: .preparationTimes) ?? [],
            nutrition: optional(NutritionInformation.self, .nutrition)
        )
    }
}
