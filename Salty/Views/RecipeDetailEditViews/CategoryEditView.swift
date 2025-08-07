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
    @Environment(\.dismiss) private var dismiss
    
    //@FetchAll(Category.order(by: \.name)) private var categories
    @FetchAll(#sql("SELECT \(Category.columns) FROM \(Category.self) ORDER BY \(Category.name) COLLATE NOCASE")) var categories: [Category]
    
    @State private var showingEditLibraryCategoriesSheet = false
    @State private var selectedCategoryIDs: Set<String> = []
    @State private var originalSelectedCategoryIDs: Set<String> = []
    @State private var showingNewCategoryAlert = false
    @State private var newCategoryName = ""
    @State private var showingDuplicateNameAlert = false
    


    var body: some View {
        VStack {
            categoryList
            
            #if os(macOS)
            macOSButtons
            #endif
        }
        .navigationTitle("Edit Categories")
        #if os(macOS)
        .padding([.top, .leading, .trailing])
        #endif
            #if !os(macOS)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .keyboardShortcut(.escape)
                }
                
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        saveChanges()
                        dismiss()
                    }
                    .keyboardShortcut(.return)
                    .disabled(selectedCategoryIDs == originalSelectedCategoryIDs)
                }
            }
            #endif
            .onAppear {
                loadSelectedCategories()
            }
            .onChange(of: categories) { _, _ in
                loadSelectedCategories()
            }
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
    
    private func categoryBinding(for categoryID: String) -> Binding<Bool> {
        Binding<Bool>(
            get: {
                selectedCategoryIDs.contains(categoryID)
            },
            set: { newVal in
                if newVal {
                    selectedCategoryIDs.insert(categoryID)
                } else {
                    selectedCategoryIDs.remove(categoryID)
                }
            }
        )
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
            originalSelectedCategoryIDs = Set(selectedIDs)
        } catch {
            selectedCategoryIDs = []
            originalSelectedCategoryIDs = []
        }
    }
    
    private func saveChanges() {
        do {
            try database.write { db in
                // Remove categories that are no longer selected
                let categoriesToRemove = originalSelectedCategoryIDs.subtracting(selectedCategoryIDs)
                for categoryId in categoriesToRemove {
                    try RecipeCategory
                        .filter(Column("recipeId") == recipe.id && Column("categoryId") == categoryId)
                        .deleteAll(db)
                }
                
                // Add newly selected categories
                let categoriesToAdd = selectedCategoryIDs.subtracting(originalSelectedCategoryIDs)
                for categoryId in categoriesToAdd {
                    let recipeCategory = RecipeCategory(id: UUID().uuidString, recipeId: recipe.id, categoryId: categoryId)
                    try recipeCategory.insert(db)
                }
            }
        } catch {
            print("Error saving category changes: \(error)")
        }
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
            }
            
            // Add to selected categories (but don't save to database yet)
            selectedCategoryIDs.insert(newCategory.id)
            newCategoryName = ""
        } catch {
            // Handle error - could add error alert here if needed
            print("Error creating category: \(error)")
        }
    }
    
    private var categoryList: some View {
        List {
            ForEach(categories) { category in
                Toggle(category.name, isOn: categoryBinding(for: category.id))
            }
            
            Button(action: {
                newCategoryName = ""
                showingNewCategoryAlert = true
            }) {
                Label("Create New Category", systemImage: "plus.circle")
            }
            .foregroundColor(.accentColor)
        }
        #if os(macOS)
        .frame(minWidth: 300, minHeight: 400)
        #else
        .frame(minWidth: 200, minHeight: 300)
        #endif
    }
    
    #if os(macOS)
    private var macOSButtons: some View {
        HStack {
            Button("Cancel") {
                dismiss()
            }
            .keyboardShortcut(.escape)
            
            Spacer()
            
            Button("Save") {
                saveChanges()
                dismiss()
            }
            .keyboardShortcut(.return)
            .buttonStyle(.borderedProminent)
            .disabled(selectedCategoryIDs == originalSelectedCategoryIDs)
        }
        .padding(.top, 4).padding(.bottom, 12)
    }
    #endif
}


#Preview {
    @Previewable @State var recipe = SampleData.sampleRecipes[0]
    CategoryEditView(recipe: $recipe)
}
