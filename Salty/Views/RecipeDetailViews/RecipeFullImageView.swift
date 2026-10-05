//
//  RecipeFullImageView.swift
//  Salty
//
//  Created by Robert on 7/6/25.
//

import SwiftUI
import SQLiteData
import SaltyCore

struct RecipeFullImageView: View {
    let recipe: Recipe
    @Environment(\.dismiss) private var dismiss
    @State private var zoom = ImageZoomState()

    var body: some View {
        ZStack(alignment: .topTrailing) {
            if let imageURL = recipe.fullImageURL {
                AsyncImage(url: imageURL) { phase in
                    switch phase {
                    case .empty:
                        ProgressView()
                            .frame(maxWidth: .infinity, maxHeight: .infinity)
                    case .success(let image):
                        ZoomableImageView(image: image, zoom: zoom)
                    case .failure:
                        ContentUnavailableView("Failed to load image", systemImage: "photo")
                    @unknown default:
                        ContentUnavailableView("Unknown error loading image", systemImage: "photo")
                    }
                }
            } else {
                ContentUnavailableView("No Image", systemImage: "photo")
            }

            // Esc closes (the cancel action), as the old key monitor did.
            // The padding is inside the label so the whole padded area takes the tap, as it did before.
            Button { dismiss() } label: {
                Label("Close", systemImage: "xmark.circle.fill")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.secondary)
                    .padding()
                    .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.cancelAction)
        }
        .navigationTitle("\(recipe.name) - Recipe Image")
        .background { ImageZoomShortcuts(zoom: zoom) }
    }
}

#Preview {
    RecipeFullImageView(recipe: SampleData.sampleRecipes[0])
}
