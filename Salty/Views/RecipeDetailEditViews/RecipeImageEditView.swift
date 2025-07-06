//
//  RecipeImageView.swift
//  Salty
//
//  Created by Robert on 5/31/23.
//

import SwiftUI
import SharingGRDB

struct RecipeImageEditView: View {
    @Binding var recipe: Recipe
    @State private var dragOver = false
    @State private var showingImagePicker = false
    
    @State var imageFrameSize: CGFloat = 100
    
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
        VStack {
            if let imageData = recipe.fullImageData, let image = createCGImage(from: imageData) {

                Image(image, scale: 1, label: Text("Recipe Image"))
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .scaledToFit()
                        .frame(width: imageFrameSize, height: imageFrameSize, alignment: .center)
                        .border(.thickMaterial)
                        .onDrop(of: ["public.image"], isTargeted: $dragOver) { providers -> Bool in
                            providers.first?.loadDataRepresentation(forTypeIdentifier: "public.image", completionHandler: { (data, error) in
                                if let data = data
                                {
                                    recipe.setImage(data)
                                }
                            })
                            return true
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                recipe.removeImage()
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                //}
//                placeholder: {
//                    ProgressView()
//                        .frame(width: 100, height: 100, alignment: .center)
//                }
            }
            else {
                RoundedRectangle(cornerRadius: 10)
                    .fill(.white)
                    .frame(width: imageFrameSize, height: imageFrameSize)
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(.regularMaterial, style: StrokeStyle(lineWidth: 4, dash: [5]))
                    )
                    .overlay(Label("Add", systemImage: "plus")
                        .foregroundColor(.gray)
                        .labelStyle(.iconOnly)
                    )
                    .onTapGesture {
                        showingImagePicker = true
                    }
                    .onDrop(of: ["public.image"], isTargeted: $dragOver) { providers -> Bool in
                        providers.first?.loadDataRepresentation(forTypeIdentifier: "public.image", completionHandler: { (data, error) in
                            if let data = data
                            {
                                recipe.setImage(data)
                            }
                        })
                        return true
                    }
            }
        }
        .fileImporter(
            isPresented: $showingImagePicker,
            allowedContentTypes: [.image],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                if let url = urls.first {
                    do {
                        // Start accessing the security-scoped resource
                        guard url.startAccessingSecurityScopedResource() else {
                            return
                        }
                        
                        defer {
                            // Stop accessing the security-scoped resource
                            url.stopAccessingSecurityScopedResource()
                        }
                        
                        let imageData = try Data(contentsOf: url)
                        recipe.setImage(imageData)
                    } catch {
                        print("Error loading image data: \(error)")
                    }
                }
            case .failure(let error):
                print("Error selecting image: \(error.localizedDescription)")
            }
        }
    }
}

#Preview {
    @Previewable @State var recipe = SampleData.sampleRecipes[0]
    return RecipeImageEditView(recipe: $recipe)
}
