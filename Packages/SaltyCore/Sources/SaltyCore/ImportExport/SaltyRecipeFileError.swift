//
//  SaltyRecipeFileError.swift
//  SaltyCore
//
//  Why a `.saltyRecipe` file couldn't be read, in words to show the person who picked it.
//

import Foundation

public enum SaltyRecipeFileError: Error, LocalizedError, Equatable {
    /// Nothing in the file but whitespace.
    case empty
    /// JSON (or not) that isn't a recipe or a list of recipes.
    case notARecipeFile

    public var errorDescription: String? {
        switch self {
        case .empty: "This file is empty."
        case .notARecipeFile: "This isn't a Salty recipe file."
        }
    }
}
