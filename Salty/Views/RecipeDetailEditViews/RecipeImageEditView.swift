//
//  RecipeImageView.swift
//  Salty
//
//  Created by Robert on 5/31/23.
//

import SwiftUI
import SharingGRDB

struct RecipeImageEditView: View {
    @State var recipe: Recipe
    @State private var dragOver = false
    
    var body: some View {
        VStack {
            Label("Image", systemImage: "photo")
                .labelStyle(TitleOnlyLabelStyle())
            
            if let imageData = recipe.imageData, let nsImage = NSImage(data: imageData) {
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
                                    recipe.imageData = data
                                }
                            })
                            return true
                        }
                        .contextMenu {
                            Button(role: .destructive) {
                                recipe.imageData = nil
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
                        print("tapped!")
                    }
                    .onDrop(of: ["public.image"], isTargeted: $dragOver) { providers -> Bool in
                        providers.first?.loadDataRepresentation(forTypeIdentifier: "public.image", completionHandler: { (data, error) in
                            if let data = data
                            {
                                recipe.imageData = data
                            }
                        })
                        return true
                    }
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
            RecipeImageEditView(recipe: recipe)
        }
    }
}
