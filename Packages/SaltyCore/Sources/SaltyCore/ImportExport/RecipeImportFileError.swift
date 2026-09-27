//
//  RecipeImportFileError.swift
//  SaltyCore
//
//  Why a recipe file couldn't be read, in words for the person who chose it. `.saltyRecipe` files
//  report through `SaltyRecipeFileError` instead.
//

import Foundation

public enum RecipeImportFileError: LocalizedError, Equatable, Sendable {
    /// An extension `RecipeImportFileKind` doesn't take, without its dot.
    case unsupportedFileType(String)
    /// The file has the right extension but isn't that app's format.
    case notA(RecipeImportFileKind)

    public var errorDescription: String? {
        switch self {
        case .unsupportedFileType(let fileExtension):
            return fileExtension.isEmpty
                ? "Salty can't import a file without an extension."
                : "Salty can't import .\(fileExtension) files."
        case .notA(let kind):
            return "This isn't a \(kind.displayName) recipe file."
        }
    }
}
