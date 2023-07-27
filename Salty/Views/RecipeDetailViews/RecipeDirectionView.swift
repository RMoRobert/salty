//
//  RecipeIngredientView.swift
//  Salty
//
//  Created by Robert on 6/26/23.
//

import SwiftUI
import RealmSwift

struct RecipeDirectionView: View {
    @ObservedRealmObject var recipe: Recipe
    var body: some View {
        VStack(alignment: .leading) {
            Grid(alignment: .leading) {
                ForEach($recipe.directions) { $direction in
                    let idx = recipe.directions.firstIndex(of: direction) ?? 0
                    GridRow(alignment: .top) {
                        Text("\(idx+1).")
                            .font(.title)
                        VStack(alignment: .leading) {
                            if (direction.stepName != "") {
                                Text(direction.stepName)
                                    .fontWeight(.semibold)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Text(direction.text)
                                .fixedSize(horizontal: false, vertical: true)
                            Spacer().frame(maxHeight: 10)
                        }
                    }
                }
            }
        }
    }
}

struct RecipeDirectionView_Previews: PreviewProvider {
    static var previews: some View {
        let realm = RecipeLibrary.previewRealm
        let lib = realm.objects(RecipeLibrary.self)
        RecipeDirectionView(recipe: lib.first!.recipes.first!)
    }
}
