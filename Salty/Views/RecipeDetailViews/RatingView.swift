//
//  RatingView.swift
//  Salty
//
//  Created by Robert on 7/3/23.
//

import Foundation
import SwiftUI
import SQLiteData
import SaltyCore

/// View-only star rating for recipes (0-5 stars)

struct RatingView: View {
    let recipe: Recipe
    let showLabel: Bool
    
    init(recipe: Recipe, showLabel: Bool = true) {
        self.recipe = recipe
        self.showLabel = showLabel
    }
    
    var body: some View {
        VStack(spacing: 8) {
            // Optional text label above the stars
            if showLabel {
                Text(recipe.rating == .notSet ? "(not set)" : "\(recipe.rating.rawValue)/5")
                    .font(.caption)
                    .foregroundStyle(recipe.rating == .notSet ? .secondary : .primary)
            }
            
            // Star rating display
            HStack(spacing: 2) {
                ForEach(1..<6) { val in
                    let isStarInRange = recipe.rating.rawValue >= val
                    Image(systemName: isStarInRange ? "star.fill" : "star")
                        .foregroundStyle(isStarInRange ? Color.ratingStar : .gray)
                        // `ratingStarOutline` is transparent except under Increase Contrast in light
                        // mode, where the outline -- not the fill -- is what carries the star's
                        // contrast. Everywhere else it draws nothing, so the plain orange star is
                        // what shows. The appearance does the switching; no colorScheme check here.
                        .overlay {
                            if isStarInRange {
                                Image(systemName: "star")
                                    .foregroundStyle(Color.ratingStarOutline)
                            }
                        }
                        .opacity(recipe.rating.rawValue > 0 ? 1 : 0.33)
                }
            }
            .accessibilityLabel(
                recipe.rating == .notSet
                    ? "Rating: not set"
                    : "Rating: \(recipe.rating.rawValue) of 5 stars"
            )
        }
    }
}

#Preview {
    VStack(spacing: 20) {
        RatingView(recipe: SampleData.sampleRecipes[1], showLabel: true)
        RatingView(recipe: SampleData.sampleRecipes[0], showLabel: false)
        RatingView(recipe: SampleData.sampleRecipes[2], showLabel: true)
    }
    .padding()
}
