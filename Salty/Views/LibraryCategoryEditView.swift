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
    @FetchAll private var categories: [Category]
    @State private var selectedCategoryIDs: Set<String> = []
    @State private var navigationPath = NavigationPath()
    
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack(path: $navigationPath) {
            List(selection: $selectedCategoryIDs) {
                ForEach(categories, id: \.id) { category in
                    NavigationLink(value: category) {
                        HStack {
                            Text(category.name)
                            //Spacer()
                        }
                    }
                }
            }
            .navigationTitle("Categories")
            .navigationDestination(for: Category.self) { category in
                LibraryCategoryEditView(category: category) {
                    // Navigate back after saving
                    navigationPath.removeLast()
                }
            }
            .navigationDestination(for: CategoryEditMode.self) { mode in
                LibraryCategoryEditView(mode: mode) {
                    // Navigate back after creating
                    navigationPath.removeLast()
                }
            }
            #if os(macOS)
            .onDeleteCommand {
                deleteSelectedCategories()
            }
            #endif
            .padding()
            .frame(minWidth: 300, minHeight: 400)
            .toolbar {
                ToolbarItem {
                    Button(action: {
                        createNewCategory()
                    }) {
                        Image(systemName: "plus")
                    }
                }
                
                ToolbarItem {
                    Button(role: .destructive, action: {
                        deleteSelectedCategories()
                    }) {
                        Image(systemName: "minus")
                    }
                    .disabled(selectedCategoryIDs.isEmpty)
                }
                
                ToolbarItem {
                    Button(action: {
                        editSelectedCategory()
                    }) {
                        Image(systemName: "pencil")
                    }
                    .disabled(selectedCategoryIDs.count != 1)
                }
                
                ToolbarItem {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    func deleteSelectedCategories() {
        try? database.write { db in
            for id in selectedCategoryIDs {
                try Category.deleteOne(db, key: id)
            }
        }
        selectedCategoryIDs.removeAll()
    }
    
    func createNewCategory() {
        navigationPath.append(CategoryEditMode.new)
    }
    
    func editSelectedCategory() {
        guard selectedCategoryIDs.count == 1,
              let selectedID = selectedCategoryIDs.first,
              let category = categories.first(where: { $0.id == selectedID }) else {
            return
        }
        navigationPath.append(category)
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
        Group {
            LibraryCategoriesEditView()
        }
    }
}

