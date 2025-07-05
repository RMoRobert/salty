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
        HStack {
            ForEach(1..<6) { val in
                if recipe.rating.rawValue >= val {
                    Image(systemName: "star.fill")
                        .symbolRenderingMode(.multicolor)
                }
                else {
                    Image(systemName: "star")
                        .foregroundStyle(.gray)
                }
            }
        }
        .accessibilityLabel("Rating: \(recipe.rating.rawValue) star(s)")
    }
}

#Preview {
    RatingView(recipe: SampleData.sampleRecipes[0])
}
