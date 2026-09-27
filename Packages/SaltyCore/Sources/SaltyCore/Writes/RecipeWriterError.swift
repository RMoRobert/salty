//
//  RecipeWriterError.swift
//  SaltyCore
//
//  Why a write in `Writes/` refused, in words a caller can show.
//

import Foundation

public enum RecipeWriterError: Error, LocalizedError, Equatable {
    /// The recipe to update isn't in the library (deleted elsewhere since it was loaded).
    case recipeNotFound(String)
    /// The id can't be a file name, so no photo can be stored under it.
    case unsafeRecipeId(String)

    public var errorDescription: String? {
        switch self {
        case .recipeNotFound: "This recipe is no longer in the library. It may have been deleted on another device."
        case .unsafeRecipeId(let id): "The recipe id \(id) can't be used as a file name, so its photo can't be stored."
        }
    }
}
