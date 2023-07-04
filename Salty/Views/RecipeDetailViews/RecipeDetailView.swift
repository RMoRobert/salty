//
//  RecipeDetailView.swift
//  Salty
//
//  Created by Robert on 6/20/23.
//

import Foundation
import SwiftUI
import RealmSwift

struct RecipeDetailView: View {
    @ObservedRealmObject var recipe: Recipe
    #if !os(macOS)
    @Environment(\.horizontalSizeClass) var horizontalSizeClass
    #else
    enum UserInterfaceSizeClass {
        case compact
        case regular
    }
    let horizontalSizeClass = UserInterfaceSizeClass.regular
    #endif
    
    var body: some View {
        let layoutHorV = horizontalSizeClass == .regular ? AnyLayout(HStackLayout()) : AnyLayout(VStackLayout())
        ScrollView {
            Section {
                layoutHorV {
                    VStack {
                        Text(recipe.name)
                            .font(.title)
                            .fontWeight(.bold)
                        if (recipe.source != "") {
                            Text(recipe.source)
                            
                        }
                        if (recipe.sourceDetails != "") {
                            Text(recipe.sourceDetails)
                        }
                        if (recipe.yield != "") {
                            Text("Yield: \(recipe.yield)")
                        }
                        
                        layoutHorV {
                            if (recipe.rating != .notSet) {
                                VStack{
                                    Text("Rating:")
                                    RatingView(rating: recipe.rating)
                                        .padding(0.25)
                                }
                            }
                            else {
                                    Text("Rating: *(not rated)*")
                            }
                            if (recipe.difficulty != .notSet) {
                                Divider()
                                HStack{
                                    Text("Difficulty:")
                                    RecipeDifficultyView(difficulty: recipe.difficulty)
                                }
                            }
                        }
                    }
                    
                    Spacer()
                        .frame(maxWidth: 50)
                    RecipeImageView(recipe: recipe)
                }
                               
            
                if (recipe.preparationTimes.count > 0) {
                    Section {
                        VStack(alignment: .leading) {
                            ForEach($recipe.preparationTimes) { $prepTime in
                                layoutHorV {
                                    Label(prepTime.name, systemImage: "clock")
                                        .fontWeight(.semibold)
                                    Text(prepTime.timeString)
                                }
                            }
                        }
                    }
//                    header: {
//                        Text("Preparation Time")
//                    .font(.title3)
//                    }
                }
                
                layoutHorV {
                    if (recipe.isFavorite) {
                        Label("Favorite", systemImage: "heart.fill")
                    }
                    if (recipe.prepared) {
                            Label("Have Prepared", systemImage: "checkmark.circle.fill")
                    }
                    if (recipe.wantToMake) {
                        Label("Want to Make", systemImage: "stove")
                    }
                }
            }
            
            Section {
                layoutHorV {
                    VStack{
                        Text("Ingredients")
                            .font(.title3)
                            .padding()
                        RecipeIngredientView(recipe: recipe)
                            .frame(minHeight: 50)
                            .padding()
                    }
                    VStack{
                        Text("Directions")
                            .font(.title3)
                            .padding()
                        RecipeDirectionView(recipe: recipe)
                            .frame(minHeight: 50)
                            .padding()
                    }
                }
            }
            
                if (recipe.notes.count > 0) {
                    Section {
                        VStack(alignment: .leading) {
                            ForEach($recipe.notes) { $note in
                                Text(note.name)
                                    .fontWeight(.semibold)
                                Text(note.text)
                            }
                        }
                    }
                    header: {
                        Text("Notes")
                            .font(.title3)
                    }
                }
        }
        .padding()
//        .headerProminence(.standard)
//        .navigationTitle(recipe.name)
    }
}


struct RecipeDetailView_Previews: PreviewProvider {
    static var previews: some View {
        let realm = RecipeLibrary.previewRealm
        let rl = realm.objects(RecipeLibrary.self)
        let r = rl.randomElement()!.recipes.randomElement()!
        Group {
            RecipeDetailView(recipe: r)
        }
    }
}
