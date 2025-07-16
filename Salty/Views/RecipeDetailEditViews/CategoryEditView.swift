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
    
    @FetchAll(Category.order(by: \.name)) private var categories
    
    @State private var showingEditLibraryCategoriesSheet = false
    @State private var selectedCategoryIDs: Set<String> = []
    @State private var showingNewCategoryAlert = false
    @State private var newCategoryName = ""
    @State private var showingDuplicateNameAlert = false

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
            
            Button(action: {
                newCategoryName = ""
                showingNewCategoryAlert = true
            }) {
                Label("Create New Category", systemImage: "plus.circle")
            }
            .foregroundColor(.accentColor)
        }
        .frame(minWidth: 200, minHeight: 300)
        #if os(macOS)
        .padding([.top, .leading, .trailing])
        #endif
        .onAppear {
            loadSelectedCategories()
        }
        .onChange(of: categories) { _, _ in
            loadSelectedCategories()
        }
//        Button("Edit…") {
//            showingEditLibraryCategoriesSheet.toggle()
//        }
//        .padding()
        .sheet(isPresented: $showingEditLibraryCategoriesSheet) {
            LibraryCategoriesEditView()
        }
        .alert("New Category", isPresented: $showingNewCategoryAlert) {
            TextField("Category Name", text: $newCategoryName)
            Button("Cancel", role: .cancel) {
                newCategoryName = ""
            }
            Button("Add") {
                createNewCategory()
            }
            .disabled(newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("Enter a name for the new category")
        }
        .alert("Category Already Exists", isPresented: $showingDuplicateNameAlert) {
            Button("OK") { }
        } message: {
            Text("A category with the name \"\(newCategoryName)\" already exists.")
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
    
    private func createNewCategory() {
        let trimmedName = newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        
        do {
            // Check if a category with this name already exists (case-insensitive)
            let existingCategory = try database.read { db in
                try Category
                    .filter(sql: "LOWER(name) = LOWER(?)", arguments: [trimmedName])
                    .fetchOne(db)
            }
            
            if existingCategory != nil {
                // Show duplicate name error
                showingDuplicateNameAlert = true
                return
            }
            
            // Create the new category
            let newCategory = Category(id: UUID().uuidString, name: trimmedName)
            try database.write { db in
                try newCategory.insert(db)
                // Automatically add the new category to the current recipe
                let recipeCategory = RecipeCategory(recipeId: recipe.id, categoryId: newCategory.id)
                try recipeCategory.insert(db)
            }
            selectedCategoryIDs.insert(newCategory.id)
            newCategoryName = ""
        } catch {
            // Handle error - could add error alert here if needed
            print("Error creating category: \(error)")
        }
    }
}


#Preview {
    @Previewable @State var recipe = SampleData.sampleRecipes[0]
    CategoryEditView(recipe: $recipe)
}
