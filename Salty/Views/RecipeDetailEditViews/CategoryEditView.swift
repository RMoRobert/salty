//
//  CategoryEditView.swift
//  Salty
//
//  Created by Robert on 6/2/23.
//

import SwiftUI
import SharingGRDB

struct CategoryEditView: View {
    @Dependency(\.defaultDatabase) private var database
    @State var recipe: Recipe
    
    @FetchAll
    //@FetchAll(Category.sort(by: \.name))
    var categories: [Category]
    
    @State private var showingEditLibraryCategoriesSheet = false
    
    var body: some View {
        List {
            ForEach(categories) { category in
                Toggle(category.name, isOn: Binding<Bool> (
                    get: {
                        do {
                            return try database.read { db in
                                try RecipeCategory
                                    .filter(Column("recipeId") == recipe.id && Column("categoryId") == category.id)
                                    .fetchOne(db) != nil
                            }
                        } catch {
                            return false
                        }
                    },
                    set: { newVal in
                        if newVal {
                            addCategory(category)
                        } else {
                            removeCategory(category)
                        }
                    }
                ))
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
    }
    
    private func addCategory(_ category: Category) {
        try? database.write { db in
            let recipeCategory = RecipeCategory(recipeId: recipe.id, categoryId: category.id)
            try recipeCategory.insert(db)
        }
    }
    
    private func removeCategory(_ category: Category) {
        try? database.write { db in
            try RecipeCategory
                .filter(Column("recipeId") == recipe.id && Column("categoryId") == category.id)
                .deleteAll(db)
        }
    }
}


//struct CategoryEditView_Previews: PreviewProvider {
//    static var previews: some View {
//        let realm = RecipeLibrary.previewRealm
//        let lib = realm.objects(RecipeLibrary.self)
//        CategoryEditView(recipe: lib.first!.recipes.first!, recipeLibrary: lib.first!)
//    }
//}
