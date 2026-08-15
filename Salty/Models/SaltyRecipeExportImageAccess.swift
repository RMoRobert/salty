//
//  SaltyRecipeExportImageAccess.swift
//  Salty
//
//  Supplies the piece of recipe export that SaltyCore can't reach: the image bytes.
//
//  SaltyCore's `fromRecipe(_:database:imageData:)` takes the photo as a parameter, because images live
//  in an app-owned folder (see RecipeImageAccess.swift). This overload fills it in from
//  `Recipe.fullImageData`, so the call sites in the app keep the shape they had before the move.
//

import Foundation
import SQLiteData
import SaltyCore

extension SaltyRecipeExport {
    /// Exports `recipe` with its photo attached, reading the bytes from the app's image folder.
    static func fromRecipe(_ recipe: Recipe, database: any DatabaseWriter) throws -> SaltyRecipeExport {
        try fromRecipe(recipe, database: database, imageData: recipe.fullImageData)
    }
}
