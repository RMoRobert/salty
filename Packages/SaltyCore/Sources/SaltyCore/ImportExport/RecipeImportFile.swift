//
//  RecipeImportFile.swift
//  SaltyCore
//
//  Purpose: Reads every importable recipe file (`.saltyRecipe`, MacGourmet `.mgourmet`, Crouton `.crumb`)
//  into `SaltyRecipeExport`s, so all of them go through `SaltyRecipeImporter`. Used by the Apple app
//  (RecipeFileImportHelper) and the C# app (SaltyCoreFFI).
//

import Foundation

public enum RecipeImportFile {

    /// The recipes in `data`, a file of the given kind, in file order.
    public static func decode(_ data: Data, kind: RecipeImportFileKind) throws -> [SaltyRecipeExport] {
        switch kind {
        case .saltyRecipe:
            return try SaltyRecipeFile.decode(data)
        case .macGourmet:
            return try macGourmetRecipes(in: data)
        case .crouton:
            return try croutonRecipes(in: data)
        }
    }

    /// The recipes in `data`, with the kind chosen from a file extension ("mgourmet" or ".crumb").
    /// `RecipeImportFileKind(fileExtension:)` decides what's accepted -- `.mgourmet4` deliberately isn't.
    public static func decode(_ data: Data, fileExtension: String) throws -> [SaltyRecipeExport] {
        let bare = fileExtension.hasPrefix(".") ? String(fileExtension.dropFirst()) : fileExtension
        guard let kind = RecipeImportFileKind(fileExtension: bare) else {
            throw RecipeImportFileError.unsupportedFileType(bare)
        }
        return try decode(data, kind: kind)
    }

    // MARK: - Formats

    /// A `.mgourmet` file: an XML property list of recipes. Categories and course travel by name, as
    /// in a `.saltyRecipe` file; "--" is MacGourmet's "no course".
    private static func macGourmetRecipes(in data: Data) throws -> [SaltyRecipeExport] {
        let recipes: [MacGourmetImportRecipe]
        do {
            recipes = try PropertyListDecoder().decode([MacGourmetImportRecipe].self, from: data)
        } catch {
            throw RecipeImportFileError.notA(.macGourmet)
        }

        return try recipes.map { macGourmet in
            var imageData: Data?
            var categories: [String]?
            var export = try SaltyRecipeExport.fromRecipe(
                macGourmet.convertToRecipe(imageData: &imageData, categories: &categories))
            export.imageData = imageData
            export.categories = categories
            if let course = macGourmet.courseName?.trimmingCharacters(in: .whitespaces), !course.isEmpty, course != "--" {
                export.course = course
            }
            return export
        }
    }

    /// A `.crumb` file holds one recipe object; an array is accepted too, so a hand-assembled or future
    /// multi-recipe file still imports. Tags travel by name.
    private static func croutonRecipes(in data: Data) throws -> [SaltyRecipeExport] {
        let decoder = JSONDecoder()
        let recipes: [CroutonImportRecipe]
        if let many = try? decoder.decode([CroutonImportRecipe].self, from: data) {
            recipes = many
        } else if let one = try? decoder.decode(CroutonImportRecipe.self, from: data) {
            recipes = [one]
        } else {
            throw RecipeImportFileError.notA(.crouton)
        }

        return try recipes.map { crumb in
            var imageData: Data?
            var tags: [String]?
            var export = try SaltyRecipeExport.fromRecipe(crumb.convertToRecipe(imageData: &imageData, tags: &tags))
            export.imageData = imageData
            export.tags = tags
            return export
        }
    }
}
