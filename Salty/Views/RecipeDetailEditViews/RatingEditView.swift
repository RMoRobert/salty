//
//  RatingView.swift
//  Salty
//
//  Created by Robert on 6/3/23.
//

import SwiftUI
import RealmSwift

struct RatingEditView: View {
    @ObservedRealmObject var recipe: Recipe
    @State private var ratingVal = Recipe.Rating.notSet
    
    
    var body: some View {
        VStack {
            Slider(value: Binding(
                get: { recipe.rating.asIndex },
                set: { val, _ in
                    let realm = recipe.realm!.thaw()
                    let thawedRecipe = recipe.thaw()!
                    try? realm.write {
                        thawedRecipe.rating = Recipe.Rating(index: val)
                    }
                }
            ), in: 0...5, step: 1)
            {
            Text("Difficulty")
                } minimumValueLabel: {
                    Text("Not Set")
                } maximumValueLabel: {
                    Text("5 Stars")
                }
                .labelsHidden()
            Text("Rating: " + recipe.rating.stringValue())
        }
        //.padding()
    }
}

struct RatingEditView_Previews: PreviewProvider {
    static var previews: some View {
        let realm = RecipeLibrary.previewRealm
        let rl = realm.objects(RecipeLibrary.self)
        let r = rl.randomElement()!.recipes.randomElement()!
        RatingEditView(recipe: r)
    }
}
