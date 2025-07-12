//
//  DifficultyView.swift
//  Salty
//
//  Created by Robert on 6/3/23.
//

import SwiftUI

struct DifficultyEditView: View {
    @Binding var recipe: Recipe
    
    var body: some View {
        Picker("Difficulty", selection: $recipe.difficulty) {
            Text("(not set)")
                .tag(Difficulty.notSet)
            
            Text("Easy")
                .tag(Difficulty.easy)
            
            Text("Somewhat Easy")
                .tag(Difficulty.somewhatEasy)
            
            Text("Medium")
                .tag(Difficulty.medium)
            
            Text("Slightly Difficult")
                .tag(Difficulty.slightlyDifficult)
            
            Text("Difficult")
                .tag(Difficulty.difficult)
        }
        .pickerStyle(.menu)
        .labelsHidden()
    }
}

#Preview {
    @Previewable @State var recipe = SampleData.sampleRecipes[0]
    return DifficultyEditView(recipe: $recipe)
}


