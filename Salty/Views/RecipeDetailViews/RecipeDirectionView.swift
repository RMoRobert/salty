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
                        if direction.isHeading != true {
                            Text("\(recipe.directions.prefix(index + 1).filter { $0.isHeading != true }.count).")
                                .font(.title)
                        } else {
                            Spacer()
                                .frame(width: 30)
                        }
                        VStack(alignment: .leading) {
                            if direction.isHeading == true {
                                Text(direction.text)
                                    .fontWeight(.semibold)
                                    .font(.callout)
                                    .fixedSize(horizontal: false, vertical: true)
                            } else {
                                Text(direction.text)
                                    .fixedSize(horizontal: false, vertical: true)
                            }
                            Spacer().frame(maxHeight: 10)
                        }
                    }
                }
            }
        }
    }
}

#Preview {
    RecipeDirectionView(recipe: SampleData.sampleRecipes[0])
}
