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
    @State private var loadedImage: NSImage?
    @State private var isLoading = false
    
    var body: some View {
        VStack {
            Label("Image", systemImage: "photo")
                .labelStyle(TitleOnlyLabelStyle())
                .hidden()
                .frame(width: 0, height: 0)
            
#if os(macOS)
            if let imageURL = recipe.fullImageURL {
                if isLoading {
                    ProgressView()
                        .frame(width: 125, height: 125)
                } else if let loadedImage = loadedImage {
                    Image(nsImage: loadedImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .scaledToFit()
                        .frame(width: 125, height: 125, alignment: .center)
                } else {
                    ProgressView()
                        .frame(width: 125, height: 125)
                        .onAppear {
                            loadImageWithDelay(from: imageURL)
                        }
                }
            }
            else {
                RoundedRectangle(cornerRadius: 10)
                    .fill(.white)
                    .frame(width: 125, height: 125)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(.regularMaterial, style: StrokeStyle(lineWidth: 4))
                    )
            }
#else
//            if let recipeImg = recipe.getImageForRecipe() {
//                Image(uiImage: recipeImg)
//                    .resizable()
//                    .aspectRatio(contentMode: .fit)
//                    .scaledToFit()
//                    .frame(width: 125, height: 125, alignment: .center)
//                    .border(.thickMaterial)
//            }
#endif
        }
    }
    
    private func loadImageWithDelay(from url: URL) {
        isLoading = true
        
        // Simulate slow loading with a 3-second delay
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0) {
            // Load the actual image
            if let imageData = try? Data(contentsOf: url),
               let image = NSImage(data: imageData) {
                DispatchQueue.main.async {
                    self.loadedImage = image
                    self.isLoading = false
                }
            } else {
                DispatchQueue.main.async {
                    self.isLoading = false
                }
            }
        }
    }
}

//struct RecipeImageView_Previews: PreviewProvider {
//    static var previews: some View {
//        RecipeImageView(recipe: Recipe())
//    }
//}
