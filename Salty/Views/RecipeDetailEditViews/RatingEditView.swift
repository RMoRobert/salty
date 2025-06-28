//
//  RatingView.swift
//  Salty
//
//  Created by Robert on 6/3/23.
//

import SwiftUI
import SharingGRDB


struct RatingEditView: View {
    @Binding var recipe: Recipe
    
    var body: some View {
        Picker("Rating", selection: $recipe.rating) {
            Text("Not Rated")
                .tag(Rating.notSet)
            
            Text("1 ⭐")
                .accessibilityLabel(Text("1 star"))
                .tag(Rating.one)
            
            Text("2 ⭐⭐")
                .accessibilityLabel(Text("2 stars"))
                .tag(Rating.two)
            
            Text("3 ⭐⭐⭐")
                .accessibilityLabel(Text("3 stars"))
                .tag(Rating.three)
            
            Text("4 ⭐⭐⭐⭐")
                .accessibilityLabel(Text("4 stars"))
                .tag(Rating.four)
            
            Text("5 ⭐⭐⭐⭐⭐")
                .accessibilityLabel(Text("5 stars"))
                .tag(Rating.five)
        }
        .pickerStyle(.menu)
        .labelsHidden()
    }
}

//struct RatingEditView_Previews: PreviewProvider {
//    static var previews: some View {
//        let realm = RecipeLibrary.previewRealm
//        let rl = realm.objects(RecipeLibrary.self)
//        let r = rl.randomElement()!.recipes.randomElement()!
//        RatingEditView(recipe: r)
//    }
//}

