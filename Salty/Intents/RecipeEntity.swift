//
//  RecipeEntity.swift
//  Salty
//
//  A recipe as Shortcuts (and so Siri, and Automator's Run Shortcut action on the Mac) sees it: the
//  "Recipe" parameter of Open Recipe, and something a shortcut can pass along and read details from --
//  above all its private link, the same `salty://recipe/<id>` that Copy Private Link puts on the
//  clipboard. Built from a library row; `RecipeEntityQuery` finds them.
//

import AppIntents
import Foundation
import SaltyCore

struct RecipeEntity: AppEntity {
    static let typeDisplayRepresentation = TypeDisplayRepresentation(
        name: "Recipe",
        numericFormat: "\(placeholder: .int) recipes"
    )
    static let defaultQuery = RecipeEntityQuery()

    /// The recipe's library id, which is what a saved shortcut remembers.
    let id: String

    @Property(title: "Name")
    var name: String

    /// Opens this recipe in Salty, on any device this library syncs to; see `RecipeLinkPasteboard`.
    @Property(title: "Private Link")
    var privateLink: URL

    @Property(title: "Favorite")
    var isFavorite: Bool

    @Property(title: "Want to Make")
    var wantToMake: Bool

    /// The picker's subtitle and picture; shown, but not details a shortcut reads.
    private let subtitle: String
    private let thumbnail: Data?

    init(recipe: Recipe) {
        id = recipe.id
        subtitle = recipe.summary.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        thumbnail = recipe.imageThumbnailData
        name = recipe.name
        privateLink = SaltyURL.recipe(id: recipe.id).url
        isFavorite = recipe.isFavorite
        wantToMake = recipe.wantToMake
    }

    var displayRepresentation: DisplayRepresentation {
        DisplayRepresentation(
            title: "\(name)",
            subtitle: subtitle.isEmpty ? nil : "\(subtitle)",
            image: thumbnail.map { DisplayRepresentation.Image(data: $0) }
        )
    }
}
