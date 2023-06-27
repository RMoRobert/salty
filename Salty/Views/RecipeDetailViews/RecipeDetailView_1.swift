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
                        if (recipe.preparationTimes.count > 0) {
                            Spacer()
                                .frame(maxHeight: 10)
                            VStack(alignment: .leading) {
                                ForEach($recipe.preparationTimes) { $prepTime in
                                    Label(prepTime.name, systemImage: "clock")
                                        .fontWeight(.semibold)
                                    Text(prepTime.timeString)
                                    Spacer().frame(maxHeight: 10)
                                }
                            }
                        }
                    }
                    Spacer()
                        .frame(maxWidth: 50)
                    RecipeImageView(recipe: recipe)
                }
                HStack {
                    Toggle("Favorite", isOn: $recipe.isFavorite)
                    Toggle("Have Prepared", isOn: $recipe.prepared)
                    Toggle("Want to Make", isOn: $recipe.wantToMake)
                }
                HStack {
                    if (recipe.rating != .notSet) {
                        Text("Rating: \(recipe.rating.stringValue())/5")
                    }
                    if (recipe.difficulty != .notSet) {
                        Text("Difficulty: \(recipe.difficulty.stringValue().localizedCapitalized)")
                    }
                }
            }
            
            Section {
                layoutHorV {
                    RecipeIngredientView(recipe: recipe)
                        .frame(minHeight: 50)
                        .padding()
                    RecipeDirectionView(recipe: recipe)
                        .frame(minHeight: 50)
                        .padding()
                }
            }
            
            if (recipe.notes.count > 0) {
                Section {
                    VStack(alignment: .leading) {
                        ForEach($recipe.notes) { $note in
                            Text(note.name)
                                .fontWeight(.semibold)
                            Text(note.text)
                            Spacer().frame(maxHeight: 10)
                        }
                    }
                }
                header: {
                    Text("Notes")
                        .font(.headline)
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
