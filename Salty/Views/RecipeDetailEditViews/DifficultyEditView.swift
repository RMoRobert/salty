//
//  DifficultyView.swift
//  Salty
//
//  Created by Robert on 6/3/23.
//

import SwiftUI
import SharingGRDB

struct DifficultyEditView: View {
    @Binding var recipe: Recipe
    
    var body: some View {
        VStack(alignment: .center) {
            Slider(
                value: Binding(
                    get: { recipe.difficulty.asIndex },
                    set: { newValue in
                        recipe.difficulty = Difficulty(index: newValue)
                    }
                ),
                in: 0...Double(Difficulty.allCases.count - 1),
                step: 1
            ) {
                //Text("Difficulty")
                // TODO: Show difficulty value!
            } minimumValueLabel: {
                Text("Not Set")
            } maximumValueLabel: {
                Text("Difficult")
            }
            .accessibilityLabel("Difficulty")
            Text(recipe.difficulty.stringValue().localizedCapitalized)
                .font(.caption)
        }
    }
}

#Preview {
    @Previewable @State var recipe = SampleData.sampleRecipes[0]
    return DifficultyEditView(recipe: $recipe)
}


