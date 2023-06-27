//
//  PreparationTimesView.swift
//  Salty
//
//  Created by Robert on 5/29/23.
//

import SwiftUI
import RealmSwift

struct PreparationTimesEditView: View {
    @ObservedRealmObject var recipe: Recipe
    //@State private var selectedIngredients = Set<Ingredient.ID>()
    var body: some View {
        Grid(verticalSpacing: 1) {
            if (recipe.preparationTimes.count > 0) {
                GridRow {
                    Group {
                        Text("Type")
                        Text("Time")
                            .gridCellColumns(2)
                    }
                    .font(.footnote)
                }
            }
            ForEach($recipe.preparationTimes) { $prepTime in
                GridRow {
                    TextField("Type", text: $prepTime.name)
                    TextField("Preparation Time", text: $prepTime.timeString)
                        .gridCellColumns(2)
                    Button(role: .destructive, action: {
                        if let idx = recipe.preparationTimes.index(of: prepTime) {
                            $recipe.preparationTimes.remove(at: idx)
                        } } ) {
                            Label("Delete", systemImage: "trash")
                                .foregroundColor(.red)
                        }
                        .buttonStyle(.plain)
                        .labelsHidden()
                }
            }
        }
        GridRow {
            Button(action: { $recipe.preparationTimes.append(PreparationTime()) } ) {
                Label("Add", systemImage: "plus")
            }
            .gridCellColumns(2)
            .gridCellAnchor(.center)
            
            Spacer()
        }
    }
}

struct PreparationTimesEditView_Previews: PreviewProvider {
    static var previews: some View {
        PreparationTimesEditView(recipe: Recipe())
    }
}
