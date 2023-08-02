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
    @State private var showingEditIngredientsSheet = false
    @State private var showingEditDirectionsSheet = false
    @Environment(\.dismiss) private var dismiss

    
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
                RecipeIngredientView(recipe: recipe)
                    //.frame(minHeight: 10)
                    .padding()
            }
            header: {
                HStack {
                    Text("Ingredients")
                        .font(.headline)
                    Button("Edit") {
                        showingEditIngredientsSheet.toggle()
                    }
                    .buttonStyle(.link)
                    .sheet(isPresented: $showingEditIngredientsSheet) {
                        IngredientsEditView(recipe: recipe)
                    }
                }
            }
            Divider()
        
            Section {
                RecipeDirectionView(recipe: recipe)
                //DirectionsEditView(recipe: recipe)
                    .frame(minHeight: 100)
                    .padding()
            }
            header: {
                HStack {
                    Text("Directions")
                        .font(.headline)
                    Button("Edit") {
                        showingEditDirectionsSheet.toggle()
                    }
                    .buttonStyle(.link)
                    .sheet(isPresented: $showingEditDirectionsSheet) {
                        DirectionsEditView(recipe: recipe)
                    }
                }
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
