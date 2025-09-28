//
//  RatingView.swift
//  Salty
//
//  Created by Robert on 6/3/23.
//

import SwiftUI


struct RatingEditView: View {
    @Binding var recipe: Recipe
    
    var body: some View {
        Picker("Rating", selection: $recipe.rating) {
            Text("Not Rated")
                .tag(Rating.notSet)
            
            Text("⭐")
                .accessibilityLabel(Text("1 star"))
                .tag(Rating.one)
            
            Text("⭐⭐")
                .accessibilityLabel(Text("2 stars"))
                .tag(Rating.two)
            
            Text("⭐⭐⭐")
                .accessibilityLabel(Text("3 stars"))
                .tag(Rating.three)
            
            Text("⭐⭐⭐⭐")
                .accessibilityLabel(Text("4 stars"))
                .tag(Rating.four)
            
            Text("⭐⭐⭐⭐⭐")
                .accessibilityLabel(Text("5 stars"))
                .tag(Rating.five)
        }
        .pickerStyle(.menu)
        .labelsHidden()
    }
}

#Preview {
    @Previewable @State var recipe = SampleData.sampleRecipes[0]
    return RatingEditView(recipe: $recipe)
}
