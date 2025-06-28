//
//  RecipeDirectionView.swift
//  Salty
//
//  Created by Robert on 6/26/23.
//

import SwiftUI
import SharingGRDB

struct RecipeDirectionView: View {
    @State var recipe: Recipe
    var body: some View {
        VStack(alignment: .leading) {
            Grid(alignment: .leading) {
                ForEach(Array(recipe.directions.enumerated()), id: \.element.hashValue) { index, direction in
                    GridRow(alignment: .top) {
                        Text("\(index+1).")
                            .font(.title)
                        VStack(alignment: .leading) {
                            if direction.stepName != nil && direction.stepName != "" {
                                Text(direction.stepName!)
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

#Preview {
    let _ = try! prepareDependencies {
        $0.defaultDatabase = try Salty.appDatabase()
    }
    @FetchAll var recipes: [Recipe]
    RecipeDirectionView(recipe: recipes.first!)
}
