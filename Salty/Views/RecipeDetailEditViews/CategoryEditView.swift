//
//  CategoryEditView.swift
//  Salty
//
//  Created by Robert on 6/2/23.
//

import SwiftUI
import SharingGRDB

//struct CategoryEditView: View {
//    @Binding var recipe: Recipe
//    var body: some View {
//        Text("test")
//    }
//        
//}

struct CategoryEditView: View {
    @Dependency(\.defaultDatabase) private var database
    @Binding var recipe: Recipe
    
    
    //@FetchAll(Category.sort(by: \.name))
    @FetchAll var categories: [Category]
    
    @State private var showingEditLibraryCategoriesSheet = false
    @State private var selectedCategoryIDs: Set<String> = []
    
    var body: some View {
        List {
            ForEach(categories) { category in
                Toggle(category.name, isOn: Binding<Bool> (
                    get: {
                        selectedCategoryIDs.contains(category.id)
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
        .onAppear {
            loadSelectedCategories()
        }
        .onChange(of: categories) { _, _ in
            loadSelectedCategories()
        }
        Button("Edit…") {
            showingEditLibraryCategoriesSheet.toggle()
        }
        .padding()
        .sheet(isPresented: $showingEditLibraryCategoriesSheet) {
            LibraryCategoriesEditView()
        }
        .onChange(of: showingEditLibraryCategoriesSheet) { _, isPresented in
            if !isPresented {
                // Refresh selected categories when the sheet is dismissed
                loadSelectedCategories()
            }
        }
    }
    
    private func loadSelectedCategories() {
        do {
            let selectedIDs = try database.read { db in
                try RecipeCategory
                    .filter(Column("recipeId") == recipe.id)
                    .fetchAll(db)
                    .map { $0.categoryId }
            }
            selectedCategoryIDs = Set(selectedIDs)
        } catch {
            selectedCategoryIDs = []
        }
    }
    
    private func addCategory(_ category: Category) {
        try? database.write { db in
            let recipeCategory = RecipeCategory(recipeId: recipe.id, categoryId: category.id)
            try recipeCategory.insert(db)
        }
        selectedCategoryIDs.insert(category.id)
    }
    
    private func removeCategory(_ category: Category) {
        let _ = try? database.write { db in
            try RecipeCategory
                .filter(Column("recipeId") == recipe.id && Column("categoryId") == category.id)
                .deleteAll(db)
        }
        selectedCategoryIDs.remove(category.id)
    }
}


#Preview {
    @Previewable @State var recipe = SampleData.sampleRecipes[0]
    CategoryEditView(recipe: $recipe)
}
