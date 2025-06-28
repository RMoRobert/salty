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
        Picker("Difficulty", selection: $recipe.difficulty) {
            Text("Not Set")
                .tag(Difficulty.notSet)
            
            Text("Easy")
                .accessibilityLabel(Text("Easy difficulty"))
                .tag(Difficulty.easy)
            
            Text("Somewhat Easy")
                .accessibilityLabel(Text("Somewhat easy difficulty"))
                .tag(Difficulty.somewhatEasy)
            
            Text("Medium")
                .accessibilityLabel(Text("Medium difficulty"))
                .tag(Difficulty.medium)
            
            Text("Slightly Difficult")
                .accessibilityLabel(Text("Slightly difficult"))
                .tag(Difficulty.slightlyDifficult)
            
            Text("Difficult")
                .accessibilityLabel(Text("Difficult"))
                .tag(Difficulty.difficult)
        }
        .pickerStyle(.menu)
        .labelsHidden()
    }
}

//struct DifficultyEditView_Previews: PreviewProvider {
//    static var previews: some View {
//        let _ = try! prepareDependencies {
//            $0.defaultDatabase = try Salty.appDatabase()
//        }
//        @FetchAll var recipes: [Recipe]
//        DifficultyEditView(recipe: recipes.first!)
//    }
//}



