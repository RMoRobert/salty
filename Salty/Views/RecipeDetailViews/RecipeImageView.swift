//
//  RecipeImageView.swift
//  Salty
//
//  Created by Robert on 5/31/23.
//

import SwiftUI
import SQLiteData
import OSLog
import SaltyCore

struct RecipeImageView: View {
    private let logger = Logger(subsystem: "Salty", category: "RecipeImage")
    @State var recipe: Recipe
    @State private var dragOver = false
    @State var imageFrameSize: CGFloat = 125
    @State private var retryCount = 0
    
    var body: some View {
        // Spacing 0: a hidden zero-size sibling used to live here and the stack's default
        // spacing above the image made the tile sit lower than it looked.
        VStack(spacing: 0) {
            if let imageURL = recipe.fullImageURL {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                            .frame(width: imageFrameSize, height: imageFrameSize)
                    case .success(let image):
                        // Fill the square and crop, so every photo makes the same clean tile; the
                        // full, uncropped image is what the tap-through shows.
                        image
                            .resizable()
                            .scaledToFill()
                            .frame(width: imageFrameSize, height: imageFrameSize, alignment: .center)
                            .clipShape(.rect(cornerRadius: 5, style: .continuous))
                    case .failure(let error):
                        // Check if it's a cancellation error and retry (see -999 cancelled sometimes on iOS -- no idea why, but this seems to work around)
                        if let urlError = error as? URLError, urlError.code == .cancelled, retryCount < 2 {
                            #if DEBUG
                            let _ = logger.debug("RecipeImageView: Retrying image load (attempt \(retryCount + 1))")
                            #endif
                            // Retry after a short delay
                            let _ = Task {
                                try? await Task.sleep(for: .seconds(0.2))
                                retryCount += 1
                            }
                            ProgressView()
                                .frame(width: imageFrameSize, height: imageFrameSize)
                        } else {
                            // Show fallback after max retries or other errors
                            RoundedRectangle(cornerRadius: 10)
                                .fill(.quaternary)
                                .frame(width: imageFrameSize, height: imageFrameSize)
                                .overlay(
                                    RoundedRectangle(cornerRadius: 10)
                                        .strokeBorder(.regularMaterial, style: StrokeStyle(lineWidth: 4))
                                )
                        }
                    @unknown default:
                        RoundedRectangle(cornerRadius: 10)
                            .fill(.quaternary)
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
                    .fill(.quaternary)
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
