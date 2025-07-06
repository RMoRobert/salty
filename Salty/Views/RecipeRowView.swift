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
    
    private func createCGImage(from imageData: Data) -> CGImage? {
        #if os(iOS)
        guard let uiImage = UIImage(data: imageData) else { return nil }
        return uiImage.cgImage
        #elseif os(macOS)
        guard let nsImage = NSImage(data: imageData) else { return nil }
        return nsImage.cgImage(forProposedRect: nil, context: nil, hints: nil)
        #endif
    }
    
    var body: some View {
        HStack {
            if let thumbnailData = recipe.imageThumbnailData {
                if let cgImage = createCGImage(from: thumbnailData) {
                    Image(cgImage, scale: 1.0, label: Text(recipe.name))
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .frame(maxWidth: 64, maxHeight: 64)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                        .shadow(radius: 2)
                        .padding(4)
                } else {
                    // Fallback if CGImage creation fails
                    Image("recipe-default")
                        .resizable()
                        .frame(width: 64, height: 64)
                        .opacity(0.15)
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                        .shadow(radius: 2)
                        .padding(4)
                }
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
    RecipeRowView(recipe: SampleData.sampleRecipes[0])
}
