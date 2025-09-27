//
//  RatingView.swift
//  Salty
//
//  Created by Robert on 7/3/23.
//

import Foundation
import SwiftUI
import SQLiteData

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
                    .foregroundColor(recipe.rating == .notSet ? .secondary : .primary)
            }
            
            // Star rating display
            HStack(spacing: 2) {
                ForEach(1..<6) { val in
                    let isStarInRange = recipe.rating.rawValue >= val
                    Image(systemName: isStarInRange ? "star.fill" : "star")
                        .symbolRenderingMode(isStarInRange ? .hierarchical : nil)
                        .foregroundColor(isStarInRange ? .yellow : .gray)
                        .shadow(radius: isStarInRange ? 0.5 : 0, x: isStarInRange ? 0.5 : 0, y: isStarInRange ? 1 : 0)
                        .opacity(recipe.rating.rawValue > 0 ? 1 : 0.33)
                }
            }
            .accessibilityLabel("Rating: \(recipe.rating == .notSet) ? 4 : \"not set\" : \"(recipe.rating.rawValue) star(s)\"")
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
