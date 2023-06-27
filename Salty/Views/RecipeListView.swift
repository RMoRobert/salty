////
////  RecipeList.swift
////  Salty
////
////  Created by Robert on 10/21/22.
////
//
//import SwiftUI
//import RealmSwift
//
//struct RecipeListView: View {
//    @ObservedRealmObject var recipeLibrary: RecipeLibrary
//    @State private var selectedRecipes = Set<Recipe>()
//    var body: some View {
//        List(selection: $selectedRecipes) {
//            
//            ForEach (recipeLibrary.recipes, id: \._id) { recipe in
//                //Section {
//                    NavigationLink(value: recipe) {
//                        RecipeRowView(recipe:  recipe)
//                    }
//                }
//                .contextMenu {
//                    Button(role: .destructive, action: {
//                        if let idx = recipeLibrary.recipes.lastIndex(of: recipe) {
//                            $recipeLibrary.recipes.remove(at: idx)
//                        }
//                    }){
//                    Text("Delete")
//                    }
//                    .keyboardShortcut(.delete, modifiers: [.command])
//                 }
//            }
//            .onDelete(perform: $recipeLibrary.recipes.remove)
//            .onMove(perform: $recipeLibrary.recipes.move)
////            .onDeleteCommand {
////                deleteSelectedRecipes()
////            }
//        }
//        .navigationTitle("Recipes")
//    }
//    
//    func deleteSelectedRecipes() -> Void {
//        for sel in selectedRecipes {
//            if let i = recipeLibrary.recipes.lastIndex(of: sel) {
//                $recipeLibrary.recipes.remove(at: i)
//            }
//        }
//    }
//}
