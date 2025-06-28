////
////  RecipeDetailView.swift
////  Salty
////
////  Created by Robert on 6/20/23.
////
//
//import Foundation
//import SwiftUI
//import SharingGRDB
//
//struct RecipeDetailViewOLD: View {
//    @State var recipe: Recipe
//    #if !os(macOS)
//    @Environment(\.horizontalSizeClass) var horizontalSizeClass
//    #else
//    enum UserInterfaceSizeClass {
//        case compact
//        case regular
//    }
//    let horizontalSizeClass = UserInterfaceSizeClass.regular
//    #endif
//    
//    var body: some View {
//        ScrollView {
//            Section {
//                HOrVStack {
//                    VStack {
//                        Text(recipe.name)
//                            .font(.title)
//                            .fontWeight(.bold)
//                        if (recipe.source != "") {
//                            Text(recipe.source)
//                            
//                        }
//                        if (recipe.sourceDetails != "") {
//                            Text(recipe.sourceDetails)
//                        }
//                        if (recipe.yield != "") {
//                            Text("Yield: \(recipe.yield)")
//                        }
//                        
//                        HOrVStack {
//                            VStack{
//                                Text("Rating:") // TODO: eliminate wrap?
//                                if (recipe.rating == .notSet) {
//                                    Text("(not rated)")
//                                        .italic()
//                                }
//                                else {
//                                    RatingView(recipe: recipe)
//                                        .padding(0.25)
//                                }
//                            }
//                            if (recipe.difficulty != .notSet) {
//                                Divider()
//                                VStack{
//                                    Text("Difficulty:")
//                                    DifficultyView(recipe: $recipe)
//                                }
//                            }
//                        }
//                    }
//                    
//                    Spacer()
//                        .frame(maxWidth: 50)
//                    RecipeImageView(recipe: recipe)
//                }
//                               
////            
////                if (recipe.preparationTimes.count > 0) {
////                    Section {
////                        VStack(alignment: .leading) {
////                            ForEach($recipe.preparationTimes) { $prepTime in
////                                HOrVStack {
////                                    Label(prepTime.name, systemImage: "clock")
////                                        .fontWeight(.semibold)
////                                    Text(prepTime.timeString)
////                                }
////                            }
////                        }
////                    }
////                    header: {
////                        Text("Preparation Time")
////                    .font(.title3)
////                    }
////                }
//                
//                HOrVStack {
//                    if (recipe.isFavorite) {
//                        Label("Favorite", systemImage: "heart.fill")
//                    }
//                    if (recipe.lastPrepared != nil) {
//                            Label("Have Prepared", systemImage: "checkmark.circle.fill")
//                            // TODO: Display last prepared date instead
//                    }
//                    if (recipe.wantToMake) {
//                        Label("Want to Make", systemImage: "stove")
//                    }
//                }
//            }
//            
//            Section {
//                HOrVStack(alignFirstTextLeadingIfHStack: true) {
//                    VStack {
//                        Text("Ingredients")
//                            .font(.title3)
//                            .padding()
//                        RecipeIngredientView(recipe: recipe)
//                            .frame(minHeight: 50)
//                            .padding()
//                    }
//                    VStack {
//                        Text("Directions")
//                            .font(.title3)
//                            .padding()
//                        RecipeDirectionView(recipe: recipe)
//                            .frame(minHeight: 50)
//                            .padding()
//                    }
//                }
//            }
//            
////                if (recipe.notes.count > 0) {
////                    Section {
////                        VStack(alignment: .leading) {
////                            ForEach($recipe.notes) { note in
////                                Text(note.name)
////                                    .fontWeight(.semibold)
////                                Text(note.text)
////                                    .fixedSize(horizontal: false, vertical: true)
////                            }
////                        }
////                    }
////                    header: {
////                        Text("Notes")
////                            .font(.title3)
////                    }
////                }
//        }
//        .padding()
//        .onDisappear {
//            print("RecipeDetailView disappeared!")
//        }
////        .headerProminence(.standard)
////        .navigationTitle(recipe.name)
//    }
//}
//
//
////struct RecipeDetailViewOLD_Previews: PreviewProvider {
////    static var previews: some View {
////        let recipe = try! prepareDependencies {
////            $0.defaultDatabase = try Salty.appDatabase()
////            return try $0.defaultDatabase.read { db in
////                try Recipe.all.fetchOne(db)!
////            }
////        }
////        Group {
////            RecipeDetailView(recipe: recipe)
////        }
////    }
////}
