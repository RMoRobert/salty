//
//  RecipeIngredientView.swift
//  Salty
//
//  Created by Robert on 6/25/23.
//

import SwiftUI
import SharingGRDB

struct RecipeIngredientView: View {
    @State var recipe: Recipe
    var body: some View {
        VStack(alignment: .leading) {
            ForEach(recipe.ingredients, id: \.hashValue) { ingredient in
                if ingredient.isHeading {
                    Text(ingredient.text)
                        .fontWeight(.semibold)
                }
                else {
                    Text(ingredient.text)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer().frame(maxHeight: 5)
                }
            }
        }
    }
}

#Preview {
    let _ = try! prepareDependencies {
        $0.defaultDatabase = try Salty.appDatabase()
    }
    @FetchAll var recipes: [Recipe]
    RecipeIngredientView(recipe: recipes.first!)
}

//struct RecipeIngredientView_Previews: PreviewProvider {
//    static var previews: some View {
//        let realm = RecipeLibrary.previewRealm
//        let lib = realm.objects(RecipeLibrary.self)
//        RecipeIngredientView(recipe: lib.first!.recipes.first!)
//    }
//}
