//
//  RecipeDetailView.swift
//  Salty
//
//  Created by Robert on 10/21/22.
//

import SwiftUI
import RealmSwift

struct RecipeDetailEditView: View {
    @ObservedRealmObject var recipe: Recipe
    @State private var showingCategoryPopover = false
    
    var body: some View {
        ScrollView {
            Section {
                HStack {
                    Form {
                        TextField("Name", text: $recipe.name)
                        TextField("Source", text: $recipe.source)
                        TextField("Source Details", text: $recipe.sourceDetails)
                        TextField("Yield", text: $recipe.yield)
                        HStack {
                            Toggle("Have Prepared", isOn: $recipe.prepared)
                            Toggle("Want to Make", isOn: $recipe.wantToMake)
                            Button("Categories") {
                                showingCategoryPopover.toggle()
                            }
                            .popover(isPresented: $showingCategoryPopover) {
                                CategoryEditView(recipe: recipe, recipeLibrary: recipe.recipeLibrary.first!)
                            }
                        }
                        HStack {
                            DifficultyEditView(recipe: recipe)
                            Spacer()
                            RatingEditView(recipe: recipe)
                        }
                        .frame(maxWidth: 500)
                    }
                    VStack {
                        Toggle("Favorite", isOn: $recipe.isFavorite)
                        Spacer()
                        RecipeImageEditView(recipe: recipe)
                        Spacer()
                    }
                }
            }
            header: {
                Text("Information")
                    .font(.headline)
            }
            Divider()
            
            Section {
                IngredientsEditView(recipe: recipe)
                    .frame(minHeight: 200)
                    .padding()
            }
            header: {
                Text("Ingredients")
                    .font(.headline)
            }
            Divider()
        
            Section {
                DirectionsEditView(recipe: recipe)
                //DirectionsEditViewOLD(recipe: recipe)
                    .frame(minHeight: 350)
                    .padding()
            }
            header: {
                Text("Directions")
                    .font(.headline)
            }
            Divider()
        
            Section {
                NotesEditView(recipe: recipe)
                    .padding()
            }
            header: {
                Text("Notes")
                    .font(.headline)
            }
            Divider()
        
            Section {
                PreparationTimesEditView(recipe: recipe)
                    .padding()
            }
            header: {
                Text("Preparation Time")
                    .font(.headline)
            }
        }
        .padding()
//        .headerProminence(.standard)
//        .navigationTitle(recipe.name)
    }
}


struct RecipeDetailEditView_Previews: PreviewProvider {
    static var previews: some View {
        let realm = RecipeLibrary.previewRealm
        let rl = realm.objects(RecipeLibrary.self)
        let r = rl.randomElement()!.recipes.randomElement()!
        Group {
            RecipeDetailEditView(recipe: r)
        }
    }
}
