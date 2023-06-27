//
//  DifficultyView.swift
//  Salty
//
//  Created by Robert on 6/3/23.
//

import SwiftUI
import RealmSwift

struct DifficultyEditView: View {
    @ObservedRealmObject var recipe: Recipe
    @State private var difficultyVal = Recipe.Difficulty.notSet
    
    
    var body: some View {
        VStack {
            Slider(value: Binding(
                get: { recipe.difficulty.asIndex },
                set: { val, _ in
                    let realm = recipe.realm!.thaw()
                    let thawedRecipe = recipe.thaw()!
                    try? realm.write {
                        thawedRecipe.difficulty = Recipe.Difficulty(index: val)
                    }
                }
            ), in: 0...5, step: 1)
            {
            Text("Difficulty")
                } minimumValueLabel: {
                    Text("Easy")
                } maximumValueLabel: {
                    Text("Difficult")
                }
                .labelsHidden()
            Text("\(recipe.difficulty.stringValue())")
        }
        //.padding()
    }
}

struct DifficultyEditView_Previews: PreviewProvider {
    static var previews: some View {
        let realm = RecipeLibrary.previewRealm
        let rl = realm.objects(RecipeLibrary.self)
        let r = rl.randomElement()!.recipes.randomElement()!
        DifficultyEditView(recipe: r)
    }
}
