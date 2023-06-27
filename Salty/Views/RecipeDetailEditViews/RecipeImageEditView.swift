//
//  RecipeImageView.swift
//  Salty
//
//  Created by Robert on 5/31/23.
//

import SwiftUI
import RealmSwift

struct RecipeImageEditView: View {
    @ObservedRealmObject var recipe: Recipe
    @State private var dragOver = false
    
    var body: some View {
        VStack {
            Label("Image", systemImage: "photo")
                .labelStyle(TitleOnlyLabelStyle())
            
#if os(OSX)
            if let recipeImageUrl = recipe.getImageUrlForRecipe() {
                AsyncImage(url: recipeImageUrl) { image in
                    image
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .scaledToFit()
                        .frame(width: 100, height: 100, alignment: .center)
                        .border(.thickMaterial)
                        .onDrop(of: ["public.image"], isTargeted: $dragOver) { providers -> Bool in
                            providers.first?.loadDataRepresentation(forTypeIdentifier: "public.image", completionHandler: { (data, error) in
                                if let data = data
                                {
                                    DispatchQueue.main.async {
                                        let _ = recipe.saveImageForRecipe(imageData: data)
                                    }
                                }
                            })
                            return true
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                let _ = recipe.deleteImageForRecipe()
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                }
                placeholder: {
                    ProgressView()
                        .frame(width: 100, height: 100, alignment: .center)
                }
            }
            else {
                RoundedRectangle(cornerRadius: 10)
                    .fill(.white)
                    .frame(width: 100, height: 100)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(.regularMaterial, style: StrokeStyle(lineWidth: 4, dash: [5]))
                    )
                    .overlay(Label("Add", systemImage: "plus")
                        .foregroundColor(.gray)
                        .labelStyle(.iconOnly)
                    )
                    .onTapGesture {
                        print("tapped!")
                    }
                    .onDrop(of: ["public.image"], isTargeted: $dragOver) { providers -> Bool in
                        providers.first?.loadDataRepresentation(forTypeIdentifier: "public.image", completionHandler: { (data, error) in
                            if let data = data
                            {
                                DispatchQueue.main.async {
                                    recipe.saveImageForRecipe(imageData: data)
                                }
                            }
                        })
                        return true
                    }
            }
#else
            if let recipeImg = recipe.getImageForRecipe() {
                Image(uiImage: recipeImg)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .scaledToFit()
                    .frame(width: 100, height: 100, alignment: .center)
                    .border(.thickMaterial)
            }
#endif
        }
    }
}

struct RecipeImageEditView_Previews: PreviewProvider {
    static var previews: some View {
        RecipeImageEditView(recipe: Recipe())
    }
}
