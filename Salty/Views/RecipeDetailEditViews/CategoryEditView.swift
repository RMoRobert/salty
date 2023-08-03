//
//  CategoryEditView.swift
//  Salty
//
//  Created by Robert on 6/2/23.
//

import SwiftUI
import RealmSwift

struct CategoryEditView: View {
    @ObservedRealmObject var recipe: Recipe
    @ObservedRealmObject var recipeLibrary: RecipeLibrary
    @State private var showingEditLibraryCategoriesSheet = false
    
    var body: some View {
 //       ScrollView {
//            VStack(alignment: .leading) {
                List {
                    ForEach(recipeLibrary.categories.sorted(byKeyPath: "name")) { category in
                        Toggle(category.name, isOn: Binding<Bool> (
                            get: {
                                if let _ = recipe.categories.index(of: category) {
                                    return true
                                }
                                else {
                                    return false
                                }
                            },
                            set: { newVal in
                                if newVal == true {
                                    addCategory(category)
                                }
                                else {
                                    removeCategory(category)
                                }
                            }
                        )
                        )
                    }
                }
                .frame(minWidth: 200, minHeight: 300)
                .padding([.top, .leading, .trailing])
                Button("Edit…") {
                    showingEditLibraryCategoriesSheet.toggle()
                }
                .padding()
                .sheet(isPresented: $showingEditLibraryCategoriesSheet) {
                    LibraryCategoriesEditView()
                }
//            }
        }
//        .frame(alignment: .leading)
//        .padding()
//    }
    
    private func addCategory(_ category: Category) -> () {
        $recipe.categories.append(category)
    }
    
    private func removeCategory(_ category: Category) -> () {
        guard let idx = recipe.categories.index(of: category) else {
            print("category not found")
            return
        }
        $recipe.categories.remove(at: idx)
    }
}

struct CategoryEditView_Previews: PreviewProvider {
    static var previews: some View {
        let realm = RecipeLibrary.previewRealm
        let lib = realm.objects(RecipeLibrary.self)
        CategoryEditView(recipe: lib.first!.recipes.first!, recipeLibrary: lib.first!)
    }
}
