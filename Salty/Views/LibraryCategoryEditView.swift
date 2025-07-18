//
//  LibraryCategoriesEditView.swift
//  Salty
//
//  Created by Robert on 6/2/23.
//

import Foundation
import SwiftUI
import SharingGRDB

struct LibraryCategoriesEditView: View {
    @Dependency(\.defaultDatabase) private var database
    
    @FetchAll(#sql("SELECT \(Category.columns) FROM \(Category.self) ORDER BY \(Category.name) COLLATE NOCASE"))
    var categories: [Category]
    
    @State private var selectedIndices: Set<Int> = []
    @State private var showingNewCategoryAlert = false
    @State private var newCategoryName = ""
    @State private var showingDuplicateNameAlert = false
    @State private var showingEditCategoryAlert = false
    @State private var editingCategoryName = ""
    @State private var editingCategoryIndex: Int? = nil
    @State private var scrollToNewItem: Bool = false
    
    @Environment(\.dismiss) var dismiss
    
    private func deleteCategory(at index: Int) {
        guard index < categories.count else { return }
        let categoryToDelete = categories[index]
        
        do {
            try database.write { db in
                // Remove from recipe associations first
                try RecipeCategory
                    .filter(Column("categoryId") == categoryToDelete.id)
                    .deleteAll(db)
                
                // Then delete the category itself
                try categoryToDelete.delete(db)
            }
            
            // Update selection indices after deletion
            var newSelection: Set<Int> = []
            for selectedIndex in selectedIndices {
                if selectedIndex < index {
                    // Keep indices before the deleted item unchanged
                    newSelection.insert(selectedIndex)
                } else if selectedIndex > index {
                    // Decrement indices after the deleted item
                    newSelection.insert(selectedIndex - 1)
                }
                // Don't add the deleted index
            }
            selectedIndices = newSelection
        } catch {
            print("Error deleting category: \(error)")
        }
    }
    
    var body: some View {
        VStack {
            categoriesList
            
            // Add, Edit, and Delete buttons
            HStack {
                Button {
                    newCategoryName = ""
                    showingNewCategoryAlert = true
                } label: {
                    #if !os(macOS)
                    Label("Add", systemImage: "plus")
                        .padding()
                    #else
                    Label("Add Category", systemImage: "plus")
                    #endif
                }
                .padding(.trailing)
                
                Button {
                    if let firstSelectedIndex = selectedIndices.min(), firstSelectedIndex < categories.count {
                        editingCategoryName = categories[firstSelectedIndex].name
                        editingCategoryIndex = firstSelectedIndex
                        showingEditCategoryAlert = true
                    }
                } label: {
                    #if !os(macOS)
                    Label("Edit", systemImage: "pencil").padding()
                    #else
                    Label("Edit Name", systemImage: "pencil")
                    #endif
                }
                .disabled(selectedIndices.count != 1)
                
                Button(role: .destructive) {
                    for index in selectedIndices.sorted(by: >) {
                        deleteCategory(at: index)
                    }
                } label: {
                    Label("Delete", systemImage: "trash")
                    #if !os(macOS)
                        .padding()
                    #endif
                }
                .disabled(selectedIndices.isEmpty)
                
                Spacer()
            }
        }
        .navigationTitle("Edit Categories")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    dismiss()
                }
            }
        }
        .padding()
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
        .alert("Rename Category", isPresented: $showingEditCategoryAlert) {
            TextField("Category name", text: $editingCategoryName)
            Button("Cancel", role: .cancel) {
                editingCategoryName = ""
                editingCategoryIndex = nil
            }
            Button("Save") {
                if let index = editingCategoryIndex {
                    updateCategoryName(at: index, to: editingCategoryName)
                }
            }
            .disabled(editingCategoryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("Enter the new name for the category")
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
            
            // Select the new category and scroll to it
            selectedIndices = [categories.count - 1]
            scrollToNewItem = true
            newCategoryName = ""
        } catch {
            print("Error creating category: \(error)")
        }
    }
    
    private func updateCategoryName(at index: Int, to newName: String) {
        guard index < categories.count else { return }
        let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        
        do {
            // Check if a category with this name already exists (case-insensitive)
            let existingCategory = try database.read { db in
                try Category
                    .filter(sql: "LOWER(name) = LOWER(?) AND id != ?", arguments: [trimmedName, categories[index].id])
                    .fetchOne(db)
            }
            
            if existingCategory != nil {
                // Show duplicate name error
                showingDuplicateNameAlert = true
                return
            }
            
            // Update the category name
            var updatedCategory = categories[index]
            updatedCategory.name = trimmedName
            try database.write { db in
                try updatedCategory.update(db)
            }
            
            editingCategoryIndex = nil
            editingCategoryName = ""
        } catch {
            print("Error updating category: \(error)")
        }
    }
    private var categoriesList: some View {
        ScrollViewReader { proxy in
            List(selection: $selectedIndices) {
                ForEach(Array(categories.enumerated()), id: \.element.id) { index, category in
                    HStack {
                        Text(category.name)
                        Spacer()
                    }
                    .tag(index)
                    .id(index)
                }
                .onDelete { indexSet in
                    for index in indexSet.sorted(by: >) {
                        deleteCategory(at: index)
                    }
                }
            }
            #if os(macOS)
            .listStyle(.bordered)
            .alternatingRowBackgrounds()
            #else
            .listStyle(.plain)
            #endif
            .onChange(of: scrollToNewItem) { _, shouldScroll in
                if shouldScroll, let lastIndex = categories.indices.last {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(lastIndex, anchor: .bottom)
                    }
                    scrollToNewItem = false
                }
            }

        }
    }
}



// MARK: - CategoryEditMode
enum CategoryEditMode: Hashable {
    case new
}

// MARK: - LibraryCategoryEditView
struct LibraryCategoryEditView: View {
    @Dependency(\.defaultDatabase) private var database
    @State private var categoryName: String
    @State private var isNewCategory: Bool
    @State private var originalCategory: Category?
    
    let onSave: () -> Void
    
    // For editing existing category
    init(category: Category, onSave: @escaping () -> Void) {
        self._categoryName = State(initialValue: category.name)
        self._isNewCategory = State(initialValue: false)
        self._originalCategory = State(initialValue: category)
        self.onSave = onSave
    }
    
    // For creating new category
    init(mode: CategoryEditMode, onSave: @escaping () -> Void) {
        self._categoryName = State(initialValue: "New Category")
        self._isNewCategory = State(initialValue: true)
        self._originalCategory = State(initialValue: nil)
        self.onSave = onSave
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Text(isNewCategory ? "New Category" : "Edit Category")
                .font(.title2)
                .fontWeight(.semibold)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Name")
                    .font(.headline)
                
                TextField("Category name", text: $categoryName)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .onSubmit {
                        saveCategory()
                    }
            }
            
            Spacer()
            
            HStack(spacing: 12) {
                Button("Cancel") {
                    onSave() // This will navigate back
                }
                .keyboardShortcut(.escape)
                
                Button(isNewCategory ? "Create" : "Save") {
                    saveCategory()
                }
                .keyboardShortcut(.return)
                .disabled(categoryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(minWidth: 300, minHeight: 200)
        .navigationTitle(isNewCategory ? "New Category" : "Edit Category")
        //.navigationBarTitleDisplayMode(.inline)
    }
    
    private func saveCategory() {
        let trimmedName = categoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        
        try? database.write { db in
            if isNewCategory {
                // Create new category
                try Category.upsert(Category.Draft(id: UUID().uuidString, name: trimmedName))
                    .execute(db)
            } else if let category = originalCategory {
                // Update existing category
                var updatedCategory = category
                updatedCategory.name = trimmedName
                try updatedCategory.update(db)
            }
        }
        
        onSave()
    }
}

struct LibraryCategoriesEditView_Previews: PreviewProvider {
    static var previews: some View {
            LibraryCategoriesEditView()
    }
}

