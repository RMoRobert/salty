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
    #if os(macOS)
    @State private var isMacOS = true
    #else
    @State private var isMacOS = false
    #endif
    @Environment(\.dismiss) private var dismiss

    
    var body: some View {
        ScrollView {
            Group {
                #if os(macOS)
                // TODO: de-duplicate, etc. (but also see what else can improve)
                Form {
                    TextField("Name", text: $recipe.name)
                    TextField("Source", text: $recipe.source)
                    TextField("Source Details", text: $recipe.sourceDetails)
                    TextField("Yield", text: $recipe.yield)
                }
                    .padding()
                #else
                VStack {
                    TextField("Name", text: $recipe.name)
                        .textFieldStyle(.roundedBorder)
                    //.padding()
                    TextField("Source", text: $recipe.source)
                        .textFieldStyle(.roundedBorder)
                    //.padding()
                    TextField("Source Details", text: $recipe.sourceDetails)
                        .textFieldStyle(.roundedBorder)
                    //.padding()
                    TextField("Yield", text: $recipe.yield)
                        .textFieldStyle(.roundedBorder)
                    //.padding()
                }
                    .padding()
                #endif
                RecipeImageEditView(recipe: recipe)
                    .padding()
                // TODO: De-duplicate, etc.
                #if os(macOS)
                HStack {
                    Toggle("Favorite", isOn: $recipe.isFavorite)
                    Toggle("Have Prepared", isOn: $recipe.prepared)
                    Toggle("Want to Make", isOn: $recipe.wantToMake)
                }
                #else
                VStack {
                    Toggle("Favorite", isOn: $recipe.isFavorite)
                        .padding(5)
                    Divider()
                    Toggle("Have Prepared", isOn: $recipe.prepared)
                        .padding(5)
                    Divider()
                    Toggle("Want to Make", isOn: $recipe.wantToMake)
                        .padding(5)
                    Divider()
                }
                .frame(maxWidth: 400)
                .padding()
                #endif
                //Divider()
                Button("Edit Categories") {
                    showingCategoryPopover.toggle()
                }
                    .padding()
                    .popover(isPresented: $showingCategoryPopover) {
                        CategoryEditView(recipe: recipe, recipeLibrary: recipe.recipeLibrary.first!)
                            .frame(minWidth: 100, minHeight: 225)
                    }
                Divider()
                HOrVStack {
                    Spacer()
                    DifficultyEditView(recipe: recipe)
                        .frame(maxWidth: 180)
                    Spacer()
                    RatingEditView(recipe: recipe)
                        .frame(maxWidth: 180)
                    
                    Spacer()
                }
                .padding()
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
                    .buttonStyle(.borderless)
                    .sheet(isPresented: $showingEditIngredientsSheet) {
                        IngredientsEditView(recipe: recipe)
                    }
                }
                .padding()
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
                    .buttonStyle(.borderless)
                    .sheet(isPresented: $showingEditDirectionsSheet) {
                        DirectionsEditView(recipe: recipe)
                    }
                }
                .padding()
            }
            Divider()
        
            Section {
                NotesEditView(recipe: recipe)
                    .frame(maxHeight: .infinity)
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
