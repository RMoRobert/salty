//
//  RecipeImageView.swift
//  Salty
//
//  Created by Robert on 5/31/23.
//

import SwiftUI
import RealmSwift

struct RecipeImageView: View {
    @ObservedRealmObject var recipe: Recipe
    @State private var dragOver = false
    
    var body: some View {
        VStack {
            Label("Image", systemImage: "photo")
                .labelStyle(TitleOnlyLabelStyle())
                .hidden()
                .frame(width: 0, height: 0)
            
#if os(macOS)
            if let recipeImageUrl = recipe.getImageUrlForRecipe() {
                AsyncImage(url: recipeImageUrl) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .scaledToFit()
                        .frame(width: 125, height: 125, alignment: .center)
                }
                placeholder: {
                    ProgressView()
                        .frame(width: 125, height: 125, alignment: .center)
                }
            }
            else {
                RoundedRectangle(cornerRadius: 10)
                    .fill(.white)
                    .frame(width: 125, height: 125)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(.regularMaterial, style: StrokeStyle(lineWidth: 4))
                    )
            }
#else
            if let recipeImg = recipe.getImageForRecipe() {
                Image(uiImage: recipeImg)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .scaledToFit()
                    .frame(width: 125, height: 125, alignment: .center)
                    .border(.thickMaterial)
            }
#endif
        }
    }
}

struct RecipeImageView_Previews: PreviewProvider {
    static var previews: some View {
        RecipeImageView(recipe: Recipe())
    }
}
