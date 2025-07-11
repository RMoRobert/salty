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
    @State private var retryCount = 0
    
    var body: some View {
        VStack {
            Label("Image", systemImage: "photo")
                .labelStyle(TitleOnlyLabelStyle())
                .hidden()
                .frame(width: 0, height: 0)
            
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
                    case .failure(let error):
                        // Check if it's a cancellation error and retry (see -999 cancelled sometimes on iOS -- no idea why, but this seems to work around)
                        if let urlError = error as? URLError, urlError.code == .cancelled, retryCount < 2 {
                            #if DEBUG
                            let _ = print("RecipeImageView: Retrying image load (attempt \(retryCount + 1))")
                            #endif
                            // Retry after a short delay
                            let _ = DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                                retryCount += 1
                            }
                            ProgressView()
                                .frame(width: imageFrameSize, height: imageFrameSize)
                        } else {
                            // Show fallback after max retries or other errors
                            RoundedRectangle(cornerRadius: 10)
                                .fill(.white)
                                .frame(width: imageFrameSize, height: imageFrameSize)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .strokeBorder(.regularMaterial, style: StrokeStyle(lineWidth: 4))
                                )
                        }
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
                .id("\(imageURL)-\(retryCount)")  // Force refresh on retry
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
        }
        .onChange(of: recipe.id) { _, _ in
            retryCount = 0
        }
    }
}

#Preview {
    let r = SampleData.sampleRecipes[0]
    RecipeImageView(recipe: r)
}
