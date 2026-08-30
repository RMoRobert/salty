//
//  ChefViewLaunch.swift
//  Salty
//
//  What the macOS "chef-view-window" scene is opened with. A Codable, Hashable window value (the
//  requirement for `WindowGroup(id:for:)`), carrying the ingredient scale along with the recipe so
//  a scaled recipe stays scaled when it moves into its own Chef View window.
//

import Foundation

struct ChefViewLaunch: Codable, Hashable {
    var recipeId: String
    /// Ingredient scale as a fraction, matching `RecipeDetailViewModel.ingredientScalePercent`
    /// (1.0 = unscaled, 0.5 = half, 2.0 = double).
    var scalePercent: Double = 1.0
}
