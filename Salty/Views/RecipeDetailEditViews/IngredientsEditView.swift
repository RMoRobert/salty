//
//  DirectionsView.swift
//  Salty
//
//  Created by Robert on 7/4/23.
//

import SwiftUI
import Tabler
import RealmSwift

struct Fruit: Identifiable {
    var id: String
    var name: String
    var weight: Double
    var color: Color
}

struct IngredientsEditView: View {
    @ObservedRealmObject var recipe: Recipe
    @State private var selectedIngredientIDs = Set<UInt64>()
    
       
    @State private var gridItems: [GridItem] = [
        GridItem(.flexible(minimum: 35, maximum: 60), alignment: .leading),
        GridItem(.flexible(minimum: 100), alignment: .leading),
        GridItem(.flexible(minimum: 40), alignment: .leading)
    ]

    private typealias Context = TablerContext<Ingredient>
    typealias BoundValue = Binding<Ingredient>

    private func header(ctx: Binding<Context>) -> some View {
        LazyVGrid(columns: gridItems) {
            Text("Qty")
            Text("Name")
            Text("Notes")
        }
        .font(.caption)
    }
    
    private func bRow(ingredient: BoundValue) -> some View {
        LazyVGrid(columns: gridItems) {
            Text(ingredient.wrappedValue.quantity)
            Text(ingredient.wrappedValue.name)
            Text(ingredient.wrappedValue.notes)
        }
    }
    
    var body: some View {
        TablerListMB(header: header,
                   row: bRow,
                   results: $recipe.ingredients,
                   selected: $selectedIngredientIDs)
        
    }
    
//    func deleteSelectedIngredients() -> () {
//        // TODO: there has to be a better way?
//        let ids = selectedIngredientIDs.map { $0 }
//            ids.forEach { theId in
//                if let theIdx = recipe.ingredients.firstIndex(where: {
//                    $0.id == theId
//                }) {
//                    $recipe.ingredients.remove(at: theIdx)
//                }
//            }
//    }
}

//struct IngredientDetailEditView: View {
//    @ObservedRealmObject var ingredient: Ingredient
//    
//    var body: some View {
//        VStack {
//                Toggle(isOn: $ingredient.isCategory) { Text("Category?") }
//                    .labelsHidden()
//                if !ingredient.isCategory {
//                    HStack { // TODO: H or V...
//                        TextField("Qty", text: $ingredient.quantity)
//                        TextField("Name", text: $ingredient.name)
//                        TextField("Notes", text: $ingredient.notes)
//                        Toggle(isOn: $ingredient.isMain) { Text("Main?") }
//                            .labelsHidden()
//                    }
//                }
//                else {
//                    TextField("Name", text: $ingredient.name)
//                        .gridCellColumns(3)
//                    Spacer()
//                }            
//        }
//    }
//}

struct IngredientsEditView_Previews: PreviewProvider {
    static var previews: some View {
        let realm = RecipeLibrary.previewRealm
        let rl = realm.objects(RecipeLibrary.self)
        let r = rl.randomElement()!.recipes.randomElement()!
        IngredientsEditView(recipe: r)
    }
}
