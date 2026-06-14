//
//  CategoryEditView.swift
//  Salty
//
//  Created by Robert on 6/2/23.
//

import SwiftUI
import SQLiteData

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
    @Binding var selectedCategoryIDs: Set<String>
    @Environment(\.dismiss) private var dismiss
    
    //@FetchAll(Category.order(by: \.name)) private var categories
    @FetchAll(#sql("SELECT \(Category.columns) FROM \(Category.self) ORDER BY \(Category.name) COLLATE NOCASE")) var categories: [Category]
    
    @State private var showingEditLibraryCategoriesSheet = false
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
                        Task {
                            await saveChanges()
                            dismiss()
                        }
                    }
                    .keyboardShortcut(.return)
                    .disabled(selectedCategoryIDs == originalSelectedCategoryIDs)
                }
            }
            #endif
            .onAppear {
                Task { await loadSelectedCategories() }
            }
            .onChange(of: categories) { _, _ in
                Task { await loadSelectedCategories() }
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
                    Task { await createNewCategory() }
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
                Task { await loadSelectedCategories() }
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
    
    private func loadSelectedCategories() async {
        let recipeId = recipe.id
        do {
            let selectedIDs = try await database.read { db in
                try RecipeCategory
                    .where { $0.recipeId.eq(recipeId) }
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

    private func saveChanges() async {
        let recipeId = recipe.id
        let categoriesToRemove = originalSelectedCategoryIDs.subtracting(selectedCategoryIDs)
        let categoriesToAdd = selectedCategoryIDs.subtracting(originalSelectedCategoryIDs)
        do {
            // First check if the recipe exists in the database
            let recipeExists = try await database.read { db in
                try Recipe
                    .where { $0.id.eq(recipeId) }
                    .fetchOne(db) != nil
            }

            // Only save category relationships if the recipe exists
            if recipeExists {
                guard !categoriesToRemove.isEmpty || !categoriesToAdd.isEmpty else { return }

                try await database.write { db in
                    for categoryId in categoriesToRemove {
                        try RecipeCategory
                            .where { $0.recipeId.eq(recipeId) && $0.categoryId.eq(categoryId) }
                            .delete()
                            .execute(db)
                    }

                    for categoryId in categoriesToAdd {
                        let recipeCategory = RecipeCategory(id: UUID().uuidString, recipeId: recipeId, categoryId: categoryId)
                        try RecipeCategory.insert { recipeCategory }.execute(db)
                    }

                    try Recipe.touchLastModified(recipeId: recipeId, in: db)
                }
            } else {
                // If recipe doesn't exist yet, the selectedCategoryIDs binding will be updated
                // and the categories will be saved when the recipe is saved
                print("Recipe not yet saved to database, category selections stored in binding")
            }
        } catch {
            print("Error saving category changes: \(error)")
        }
    }
    
    private func createNewCategory() async {
        let trimmedName = newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        do {
            // Check if a category with this name already exists (case-insensitive)
            let existingCategory = try await database.read { db in
                try Category
                    .where { $0.name.collate(.nocase).eq(trimmedName.collate(.nocase)) }
                    .fetchOne(db)
            }

            if existingCategory != nil {
                // Show duplicate name error
                showingDuplicateNameAlert = true
                return
            }

            // Create the new category
            let newCategory = Category(id: UUID().uuidString, name: trimmedName, lastModifiedDate: Date())
            try await database.write { db in
                try Category.insert {
                    newCategory
                }.execute(db)
            }

            // Add to selected categories
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
                Task {
                    await saveChanges()
                    dismiss()
                }
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
    @Previewable @State var selectedCategoryIDs = Set<String>()
    CategoryEditView(recipe: $recipe, selectedCategoryIDs: $selectedCategoryIDs)
}
