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
                Image(systemName: "list.bullet.rectangle")
                    .font(.system(size: 32, weight: .light))
                    .foregroundColor(.gray.opacity(0.4))
                    .frame(width: 64, height: 64)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(.gray.opacity((0.06)))
                            .shadow(radius: 2)
                    )
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
                Spacer()
                HStack {
                    if (recipe.rating != .notSet) {
                        HStack(alignment: .bottom, spacing: 0) {
                            ForEach(1..<6) { starNum in
                                Image(systemName: recipe.rating.rawValue >= starNum ? "star.fill" : "star")
                                    .foregroundColor(.secondary)
                                    .font(.caption2)
                                    .modifier(IconShadowModifier())
                                    .accessibilityHidden(true)
                            }
                        }
                        .accessibilityHint("Rating: \(recipe.rating.rawValue) stars")
                    }
                    else {
                        HStack(alignment: .bottom, spacing: 0) {
                            ForEach(1..<6) { starNum in
                                Image(systemName: "circle.dotted")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                    .accessibilityHidden(true)
                            }
                        }
                        .hidden()
                        .accessibilityHint("Recipe not rated")
                        
                    }
                    Spacer()
                    Image(systemName: recipe.isFavorite ? "heart.fill" : "heart.slash")
                        .font(.caption)
                        .foregroundColor(.red)
                        .modifier(IconShadowModifier())
                        .opacity(recipe.isFavorite ? 100 : 0)
                        .accessibilityHint(recipe.isFavorite ? "Is Favorite" : "Not Favorite")
                }
                Spacer()
            }
        }
    }
    
    struct IconShadowModifier: ViewModifier {
        func body(content: Content) -> some View {
            content
                .shadow(radius: 0.5, x:0.5, y:1)
        }
    }
    
}


#Preview {
    RecipeRowView(recipe: SampleData.sampleRecipes[0])
}
