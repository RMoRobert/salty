//
//  RecipeHtmlPage.swift
//  SaltyCore
//

import Foundation

/// One recipe's worth of input to `RecipeHtmlDocument`: the recipe plus the pieces that live outside it
/// (library names come from other tables; the photo is inlined as base64 by the app, see the app's
/// `Recipe.htmlPage(database:)`).
public struct RecipeHtmlPage {
    public var recipe: Recipe
    public var course: String?
    public var categories: [String]
    public var tags: [String]
    public var imageBase64: String?

    public init(recipe: Recipe, course: String? = nil, categories: [String] = [], tags: [String] = [],
                imageBase64: String?) {
        self.recipe = recipe
        self.course = course
        self.categories = categories
        self.tags = tags
        self.imageBase64 = imageBase64
    }
}
