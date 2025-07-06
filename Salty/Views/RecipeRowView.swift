//
//  RecipeRowView.swift
//  Salty
//
//  Created by Robert on 10/21/22.
//

import SwiftUI
import SharingGRDB


func createXPImage(_ value: Data) -> Image {
#if canImport(UIKit)
    let songArtwork: UIImage = UIImage(data: value) ?? UIImage()
    return Image(uiImage: songArtwork)
#elseif canImport(AppKit)
    let songArtwork: NSImage = NSImage(data: value) ?? NSImage()
    return Image(nsImage: songArtwork)
#else
    return Image(systemImage: "some_default")
#endif
}

struct RecipeRowView: View {
    let recipe: Recipe
    
    var body: some View {
        HStack {
            if let thumbnailData = recipe.imageThumbnailData {
                createXPImage(thumbnailData)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(maxWidth: 64, maxHeight: 64)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .shadow(radius: 2)
                    .padding(4)
            } else {
                // Show default recipe image when no thumbnail data
                Image("recipe-default")
                    .resizable()
                    .frame(width: 64, height: 64)
                    .opacity(0.10)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .shadow(radius: 2)
                    .padding(4)
            }
            VStack(alignment: .leading) {
                Spacer()
                VStack(alignment: .leading) {
                    Text(recipe.name)
                        .fontWeight(.semibold)
                        .multilineTextAlignment(.leading)
                        .lineLimit(1)
                    Text(recipe.summary)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
                //if (recipe.rating != .notSet) {
                    Spacer()
                    HStack(alignment: .bottom, spacing: 0) {
                        ForEach(1..<6) { starNum in
                            Image(systemName: recipe.rating.rawValue >= starNum ? "star.fill" : "star")
                                .foregroundColor(recipe.rating != .notSet ? .accentColor : .gray )
                                .font(.caption)
                                .accessibilityHidden(true)
                        }
                    }
                    .accessibilityHint(recipe.rating != .notSet ? "Rating: \(recipe.rating.rawValue) stars" : "Recipe not rated")
                    .padding([.leading, .trailing], 0)
                    Spacer()
                    
                //}
                Spacer()
            }
        }
    }
}

#Preview {
    RecipeRowView(recipe: SampleData.sampleRecipes[0])
}
