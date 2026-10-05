//
//  RecipeExporter.swift
//  SaltyCore
//
//  Turns recipes into an export file — `.saltyRecipe`, schema.org JSON-LD, or HTML — with the name a
//  save panel should suggest. One path for every format and for one recipe or several, so the rules
//  (one recipe as a bare object, several as an array; "Name.ext" or "3_recipes.ext") live in one place
//  instead of being repeated per format and per menu command.
//
//  Photos live in a folder the app owns, so the app hands them in through the two closures.
//

import Foundation
import GRDB

/// What to export recipes as.
public enum RecipeExportFormat: Sendable, Equatable {
    /// Salty's own `.saltyRecipe` file, which every Salty client imports.
    case saltyFile
    /// schema.org/Recipe JSON-LD, readable by other recipe apps.
    case jsonLD
    /// A standalone HTML page, one `<main>` per recipe.
    case html(HTMLExportOptions)

    /// The file extension, without the dot.
    public var fileExtension: String {
        switch self {
        case .saltyFile: SaltyRecipeFile.fileExtension
        case .jsonLD: "json"
        case .html: "html"
        }
    }
}

/// An export ready to save: its bytes and a suggested file name.
public struct RecipeExportFile: Sendable, Equatable {
    public let data: Data
    public let fileName: String
    public let format: RecipeExportFormat
}

public enum RecipeExportError: Error, Equatable, Sendable {
    /// No recipes were given, so there is nothing to write.
    case nothingToExport
}

public struct RecipeExporter: Sendable {
    /// The recipe's photo as stored, or nil when it has none. Goes into `.saltyRecipe` files.
    private let imageData: @Sendable (Recipe) -> Data?
    /// The recipe's photo as base64 for inlining into HTML, or nil when it has none.
    private let htmlImageBase64: @Sendable (Recipe) -> String?

    public init(imageData: @escaping @Sendable (Recipe) -> Data?,
                htmlImageBase64: @escaping @Sendable (Recipe) -> String?) {
        self.imageData = imageData
        self.htmlImageBase64 = htmlImageBase64
    }

    /// `recipes`, in the order given, as one file of `format`. Library names (course, categories, tags)
    /// are read from `database`.
    public func export(_ recipes: [Recipe], as format: RecipeExportFormat,
                       database: any DatabaseWriter) throws -> RecipeExportFile {
        guard let first = recipes.first else { throw RecipeExportError.nothingToExport }

        let data: Data
        switch format {
        case .saltyFile:
            let exports = try recipes.map {
                try SaltyRecipeExport.fromRecipe($0, database: database, imageData: imageData($0))
            }
            data = try SaltyRecipeFile.encode(exports)

        case .jsonLD:
            let items = recipes.map { recipe in
                let names = recipe.libraryNames(database: database)
                let metadata = SchemaOrgRecipeJSONLDExporter.LibraryMetadata(
                    courseName: names.course, categoryNames: names.categories, tagNames: names.tags)
                return (recipe: recipe, metadata: metadata)
            }
            data = try SchemaOrgRecipeJSONLDExporter().data(for: items)

        case .html(let options):
            let pages = recipes.map { recipe in
                let names = recipe.libraryNames(database: database)
                return RecipeHtmlPage(recipe: recipe, course: names.course, categories: names.categories,
                                      tags: names.tags, imageBase64: htmlImageBase64(recipe))
            }
            let title = recipes.count == 1 ? first.name : "\(recipes.count) Recipes"
            data = Data(RecipeHtmlDocument.render(pages, options: options, title: title).utf8)
        }

        return RecipeExportFile(data: data, fileName: Self.fileName(for: recipes, format: format), format: format)
    }

    /// "Name.ext" for one recipe, "3_recipes.ext" for several.
    public static func fileName(for recipes: [Recipe], format: RecipeExportFormat) -> String {
        let stem = recipes.count == 1 ? recipes[0].name : "\(recipes.count)_recipes"
        return "\(stem).\(format.fileExtension)"
    }
}
