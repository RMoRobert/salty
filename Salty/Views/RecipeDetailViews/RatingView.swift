//
//  RatingView.swift
//  Salty
//
//  Created by Robert on 7/3/23.
//

import Foundation
import SwiftUI

/// View-only star rating for recipes (0-5 stars)

struct RatingView: View {
    let recipe: Recipe
    
    var body: some View {
        HStack(spacing: 2) {
            ForEach(1..<6) { val in
                let isStarInRange = recipe.rating.rawValue >= val
                Image(systemName: isStarInRange ? "star.fill" : "star")
                    .symbolRenderingMode(isStarInRange ? .hierarchical : nil)
                    .foregroundColor(isStarInRange ? .yellow : .gray)
                    .shadow(radius: isStarInRange ? 0.5 : 0, x: isStarInRange ? 0.5 : 0, y: isStarInRange ? 1 : 0)                
            }
        }
        .accessibilityLabel("Rating: \(recipe.rating.rawValue) star(s)")
    }
}

#Preview {
    RatingView(recipe: SampleData.sampleRecipes[0])
}
