//
//  RecipeRowView.swift
//  Salty
//
//  Created by Robert on 10/21/22.
//

import SwiftUI

func createXPImage(_ data: Data) -> Image {
#if canImport(UIKit)
    let imageFromData: UIImage = UIImage(data: data) ?? UIImage()
    return Image(uiImage: (UIKit))
#elseif canImport(AppKit)
    let (UIKit): NSImage = NSImage(data: data) ?? NSImage()
    return Image(nsImage: (UIKit))
#else
    return Image(systemImage: "some_default")
#endif
}

struct RecipeRowView: View {
    @AppStorage("listViewStyle") private var listViewStyle: RecipeListViewStyle = .summary
    let recipe: Recipe
    private var hasBottomRowData: Bool {
        recipe.rating != .notSet
    }
    private var favoriteHeartView: ModifiedContent<some View, AccessibilityAttachmentModifier> {
        Image(systemName: recipe.isFavorite ? "heart.fill" : "heart.slash")
            .font(.caption)
            .foregroundColor(.red)
            .modifier(IconShadowModifier())
            .opacity(recipe.isFavorite ? 100 : 0)
            .accessibilityHint(recipe.isFavorite ? "Is Favorite" : "Not Favorite")
    }
    
    var body: some View {
        HStack {
            if let thumbnailData = recipe.imageThumbnailData {
                createXPImage(thumbnailData)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: listViewStyle == .smallIcons ? 32 : 64, height: listViewStyle == .smallIcons ? 32 : 64)
                    .clipShape(RoundedRectangle(cornerRadius: 5))
                    .shadow(radius: 2)
                    .padding(4)
            } else {
                // Show default recipe image when no thumbnail data
                Image(systemName: "list.bullet.rectangle")
                    .font(.system(size: listViewStyle == .smallIcons ? 24 : 32, weight: .light))
                    .foregroundColor(.gray.opacity(0.4))
                    .frame(width: listViewStyle == .smallIcons ? 32 : 64, height: listViewStyle == .smallIcons ? 32 : 64)
                    .background(
                        RoundedRectangle(cornerRadius: 5)
                            .fill(.gray.opacity((0.06)))
                            .shadow(radius: 2)
                    )
                    .padding(4)
            }
            VStack(alignment: .leading) {
                if listViewStyle == .summary {
                    Spacer()
                }
                VStack(alignment: .leading) {
                    Text(recipe.name)
                        .fontWeight(.semibold)
                        .multilineTextAlignment(.leading)
                        .lineLimit(1)
                    if listViewStyle == .summary || (!hasBottomRowData && !recipe.isFavorite) {
                        Text(recipe.summary)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                    }
                    else if !hasBottomRowData && recipe.isFavorite {
                        HStack {
                            Text(recipe.summary)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                            Spacer()
                            favoriteHeartView
                        }
                        
                    }
                }
                if listViewStyle == .summary {
                    Spacer()
                }
                if (listViewStyle == .summary || hasBottomRowData) {
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
                        favoriteHeartView
                    }
                }
                if listViewStyle == .summary {
                    Spacer()
                }
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
