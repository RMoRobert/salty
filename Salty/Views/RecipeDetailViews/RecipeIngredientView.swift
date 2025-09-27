//
//  RecipeIngredientView.swift
//  Salty
//
//  Created by Robert on 6/25/23.
//

import SwiftUI
import SQLiteData

struct RecipeIngredientView: View {
    @State var recipe: Recipe
    var body: some View {
        VStack(alignment: .leading) {
            ForEach(recipe.ingredients, id: \.hashValue) { ingredient in
                if ingredient.isHeading {
                    Text(ingredient.text)
                        .fontWeight(.semibold)
                }
                else {
                    Text(ingredient.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer().frame(maxHeight: 5)
                }
            }
        }
    }
}

#Preview {
    RecipeIngredientView(recipe: SampleData.sampleRecipes[0])
}
