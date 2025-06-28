////
////  RecipeDetailView.swift
////  Salty
////
////  Created by Robert on 10/21/22.
////
//
//import SwiftUI
//import SharingGRDB
//
//struct RecipeDetailEditView: View {
//    @State var recipe: Recipe
//    @State private var showingCategoryPopover = false
//    @State private var showingEditIngredientsSheet = false
//    @State private var showingEditDirectionsSheet = false
////    #if os(macOS)
////    @State private var isMacOS = true
////    #else
////    @State private var isMacOS = false
////    #endif
////    @Environment(\.dismiss) private var dismiss
//
//    
//    var body: some View {
//        ScrollView {
//            Group {
//                // TODO: de-duplicate, etc. (but also see what else can improve)
//                Form {
//                    TextField("Name", text: $recipe.name)
//                    TextField("Source", text: $recipe.source)
//                    TextField("Source Details", text: $recipe.sourceDetails)
//                    TextField("Yield", text: $recipe.yield)
//                }
//                    .padding()
//               // RecipeImageEditView(recipe: recipe)
//               //     .padding()
//                HStack {
//                    Toggle("Favorite", isOn: $recipe.isFavorite)
//                    Toggle("Have Prepared", isOn: $recipe.prepared)
//                    Toggle("Want to Make", isOn: $recipe.wantToMake)
//                }
//                //Divider()
//                Button("Edit Categories") {
//                    showingCategoryPopover.toggle()
//                }
//                .padding()
//                .popover(isPresented: $showingCategoryPopover) {
//                    CategoryEditView(recipe: recipe, recipeLibrary: recipe.recipeLibrary.first!)
//                        .frame(minWidth: 100, minHeight: 225)
//                }
//                Divider()
//                HOrVStack {
//                    Spacer()
//                    DifficultyEditView(recipe: recipe)
//                        .frame(maxWidth: 180)
//                    Spacer()
//                    RatingEditView(recipe: recipe)
//                        .frame(maxWidth: 180)
//                    
//                    Spacer()
//                }
//                .padding()
//            }
//            Divider()
//            
//            Section {
//                RecipeIngredientView(recipe: recipe)
//                    //.frame(minHeight: 10)
//                    .padding()
//            }
//            header: {
//                HStack {
//                    Text("Ingredients")
//                        .font(.headline)
//                    Button("Edit") {
//                        showingEditIngredientsSheet.toggle()
//                    }
//                    .buttonStyle(.borderless)
//                    .sheet(isPresented: $showingEditIngredientsSheet) {
//                        IngredientsEditView(recipe: recipe)
//                    }
//                }
//                .padding()
//            }
//            Divider()
//        
//            Section {
//                RecipeDirectionView(recipe: recipe)
//                //DirectionsEditView(recipe: recipe)
//                    .frame(minHeight: 100)
//                    .padding()
//            }
//            header: {
//                HStack {
//                    Text("Directions")
//                        .font(.headline)
//                    Button("Edit") {
//                        showingEditDirectionsSheet.toggle()
//                    }
//                    .buttonStyle(.borderless)
//                    .sheet(isPresented: $showingEditDirectionsSheet) {
//                        DirectionsEditView(recipe: recipe)
//                    }
//                }
//                .padding()
//            }
//            Divider()
//        
//            Section {
//                NotesEditView(recipe: recipe)
//                    .frame(maxHeight: .infinity)
//                    .padding()
//            }
//            header: {
//                Text("Notes")
//                    .font(.headline)
//            }
//            Divider()
//        
//            Section {
//                PreparationTimesEditView(recipe: recipe)
//                    .padding()
//            }
//            header: {
//                Text("Preparation Time")
//                    .font(.headline)
//            }
//        }
//        .padding()
////        .headerProminence(.standard)
////        .navigationTitle(recipe.name)
//    }
//}
//
//
//struct RecipeDetailEditView_Previews: PreviewProvider {
//    static var previews: some View {
//        let recipe = try! prepareDependencies {
//            $0.defaultDatabase = try Salty.appDatabase()
//            return try $0.defaultDatabase.read { db in
//                try Recipe.all.fetchOne(db)!
//            }
//        }
//        Group {
//            RecipeDetailEditView(recipe: recipe)
//        }
//    }
//}
