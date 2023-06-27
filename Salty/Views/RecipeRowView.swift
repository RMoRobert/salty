//
//  RecipeRowView.swift
//  Salty
//
//  Created by Robert on 10/21/22.
//

import SwiftUI
import RealmSwift

struct RecipeRowView: View {
    @ObservedRealmObject var recipe: Recipe   
    
    var body: some View {
        HStack {
            if let imageUrl = recipe.getImageUrlForRecipe() {
                AsyncImage(url: imageUrl) { image in
                    image
                        .resizable()
                        .scaledToFill()
                        .frame(width: 64, height: 64)
                        //.clipped()
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                        .shadow(radius: 2)
                        .padding(4)
                } placeholder: {
                    ProgressView()
                        .frame(width: 64, height: 64)
                }
            }
            else {
                Image("recipe-default")
                    .resizable()
                    .frame(width: 64, height: 64)
                    .opacity(0.15)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .shadow(radius: 2)
                    .padding(4)
            }
            VStack(alignment: .leading) {
                Text(recipe.name)
                    .fontWeight(.semibold)
                    .multilineTextAlignment(.leading)
                    .lineLimit(2)
                let secondaryText: String = recipe.introduction != "" ? recipe.introduction : (recipe.source != "" ? recipe.source : (recipe.sourceDetails != "" ? recipe.sourceDetails : ""))
                Text(secondaryText)
                    .foregroundColor(Color.gray)
                    .lineLimit(1)
            }
        }
    }
}

struct RecipeRowView_Previews: PreviewProvider {
    static var previews: some View {
        VStack {
            RecipeRowView(recipe: Recipe())
            RecipeRowView(recipe: Recipe())
        }
        //.previewLayout(.fixed(width: 300, height: 70))
    }
}
