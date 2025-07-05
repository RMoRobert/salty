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
    
    var body: some View {
        VStack {
            Label("Image", systemImage: "photo")
                .labelStyle(TitleOnlyLabelStyle())
            
            if let imageData = recipe.fullImageData, let nsImage = NSImage(data: imageData) {

                Image(nsImage: nsImage)
                        .resizable()
                        .aspectRatio(contentMode: .fit)
                        .scaledToFit()
                        .frame(width: 100, height: 100, alignment: .center)
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

struct RecipeImageEditView_Previews: PreviewProvider {
    static var previews: some View {
        let recipe = try! prepareDependencies {
            $0.defaultDatabase = try Salty.appDatabase()
            return try $0.defaultDatabase.read { db in
                try Recipe.all.fetchOne(db)!
            }
        }
        Group {
            RecipeImageEditView(recipe: .constant(recipe))
        }
    }
}
