//
//  RecipeImageView.swift
//  Salty
//
//  Created by Robert on 5/31/23.
//

import SwiftUI
import SharingGRDB

struct RecipeImageView: View {
    @State var recipe: Recipe
    @State private var dragOver = false
    @State var imageFrameSize: CGFloat = 125
    
    var body: some View {
        VStack {
            Label("Image", systemImage: "photo")
                .labelStyle(TitleOnlyLabelStyle())
                .hidden()
                .frame(width: 0, height: 0)
            
#if os(macOS)
            if let imageURL = recipe.fullImageURL {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                            .frame(width: imageFrameSize, height: imageFrameSize)
                    case .success(let image):
                        image
                            .resizable()
                            .aspectRatio(contentMode: .fit)
                            .scaledToFit()
                            .frame(width: imageFrameSize, height: imageFrameSize, alignment: .center)
                    case .failure(_):
                        RoundedRectangle(cornerRadius: 10)
                            .fill(.white)
                            .frame(width: imageFrameSize, height: imageFrameSize)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .strokeBorder(.regularMaterial, style: StrokeStyle(lineWidth: 4))
                            )
                    @unknown default:
                        RoundedRectangle(cornerRadius: 10)
                            .fill(.white)
                            .frame(width: imageFrameSize, height: imageFrameSize)
                            .overlay(
                                RoundedRectangle(cornerRadius: 10)
                                    .strokeBorder(.regularMaterial, style: StrokeStyle(lineWidth: 4))
                            )
                    }
                }
            }
            else {
                RoundedRectangle(cornerRadius: 10)
                    .fill(.white)
                    .frame(width: imageFrameSize, height: imageFrameSize)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(.regularMaterial, style: StrokeStyle(lineWidth: 4))
                    )
            }
#else
                // TODO: something similar for iOS using UIImage instead of NSImage, and any other changes that may be needed.
#endif
        }
    }
}

#Preview {
    let r = SampleData.sampleRecipes[0]
    RecipeImageView(recipe: r)
}
