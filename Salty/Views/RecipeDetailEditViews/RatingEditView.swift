//
//  RatingView.swift
//  Salty
//
//  Created by Robert on 6/3/23.
//

import SwiftUI
import RealmSwift

//struct RatingEditView: View {
//    @ObservedRealmObject var recipe: Recipe
//    @State private var ratingVal = Recipe.Rating.notSet
//    @State private var selectedRating = Recipe.Rating.notSet
//
//
//    var body: some View {
//        VStack {
//            Picker("Rating", selection: $selectedRating) {
//                Text("(not set)")
//                    .tag(Recipe.Rating.notSet)
//                    .id(0)
//                StarView(numberOfStars: 1)
//                    .tag(Recipe.Rating.one)
//                    .id(1)
//                StarView(numberOfStars: 2)
//                    .tag(Recipe.Rating.two)
//                    .id(2)
//                StarView(numberOfStars: 3)
//                    .tag(Recipe.Rating.three)
//                    .id(3)
//                StarView(numberOfStars: 4)
//                    .tag(Recipe.Rating.four)
//                    .id(4)
//                StarView(numberOfStars: 5)
//                    .tag(Recipe.Rating.five)
//                    .id(5)
//            }
//        }
//    }
//}
//
//struct StarView: View {
//    @State var numberOfStars: Int
//    var body: some View  {
//        Group {
//            HStack {
//                ForEach(1..<6, id: \.self) { val in
//                    let _ = print("val = \(val)")
//                    Label {
//                        Text("\(val) stars")
//                    }
//                icon: {
//                        if numberOfStars > val {
//                            Image(systemName: "star.fill")
//                        }
//                        else {
//                            Image(systemName: "star")
//                        }
//                    }
//
//                }
//                Text("\(numberOfStars) stars")
//            }
//            .accessibilityLabel("\(numberOfStars) star(s)")
//        }
//    }
//}

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
