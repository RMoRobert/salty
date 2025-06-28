//
//  RecipeRowView.swift
//  Salty
//
//  Created by Robert on 10/21/22.
//

import SwiftUI
import SharingGRDB

struct RecipeRowView: View {
    let recipe: Recipe
    
    var body: some View {
        HStack {
            if recipe.imageData != nil, let imageData = recipe.imageData {
                let img = NSImage(data: imageData)
                Image(nsImage: img ?? NSImage())
                    .resizable()
                    .scaledToFill()
                    .frame(width: 64, height: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .shadow(radius: 2)
                    .padding(4)
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
                Text(recipe.summary)
                    .foregroundColor(Color.gray)
                    .lineLimit(1)
            }
        }
    }
}

#Preview {
    let _ = try! prepareDependencies {
      $0.defaultDatabase = try Salty.appDatabase()
    }
    @FetchAll var recipes: [Recipe]
    RecipeRowView(recipe: recipes.first!)
}
