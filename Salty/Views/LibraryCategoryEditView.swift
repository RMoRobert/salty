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
    @State private var isEditMode = false
    @State private var editingCategory: Category?
    @State private var editingName = ""
    @State private var isCreatingNew = false
    
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        List(selection: $selectedCategoryIDs) {
            ForEach(categories, id: \.id) { category in
                HStack {
                    Text(category.name)
                        .onTapGesture(count: 2) {
                            editingCategory = category
                            editingName = category.name
                        }
                        .popover(isPresented: .constant(editingCategory?.id == category.id || isCreatingNew)) {
                            EditCategoryPopover(
                                categoryName: $editingName,
                                isNewCategory: isCreatingNew,
                                onSave: isCreatingNew ? saveNewCategory : saveCategoryName,
                                onCancel: {
                                    editingCategory = nil
                                    isCreatingNew = false
                                    editingName = ""
                                }
                            )
                        }
                    
                    Spacer()
                }
            }
        }
        .onDeleteCommand {
            deleteSelectedCategories()
        }
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
    
    
    func deleteSelectedCategories() {
        try? database.write { db in
            for id in selectedCategoryIDs {
                try Category.deleteOne(db, key: id)
            }
        }
        selectedCategoryIDs.removeAll()
    }
    
    func saveCategoryName() {
        guard let category = editingCategory else { return }
        let trimmedName = editingName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        
        try? database.write { db in
            var updatedCategory = category
            updatedCategory.name = trimmedName
            try updatedCategory.update(db)
        }
        
        editingCategory = nil
    }
    
    func createNewCategory() {
        editingName = "New Category"
        isCreatingNew = true
    }
    
    func saveNewCategory() {
        let trimmedName = editingName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        
        try? database.write { db in
            try Category.upsert(Category.Draft(id: UUID().uuidString, name: trimmedName))
                .execute(db)
        }
        
        isCreatingNew = false
        editingName = ""
    }
    
    func deleteCategory(id: String) {
        try? database.write { db in
            try Category.deleteOne(db, key: id)
        }
    }
    
    func editSelectedCategory() {
        guard selectedCategoryIDs.count == 1,
              let selectedID = selectedCategoryIDs.first,
              let category = categories.first(where: { $0.id == selectedID }) else {
            return
        }
        
        editingCategory = category
        editingName = category.name
    }
}

struct EditCategoryPopover: View {
    @Binding var categoryName: String
    let isNewCategory: Bool
    let onSave: () -> Void
    let onCancel: () -> Void
    
    var body: some View {
        VStack(spacing: 16) {
            Text(isNewCategory ? "New Category" : "Edit Category")
                .font(.headline)
            
            TextField("Category name", text: $categoryName)
                .textFieldStyle(RoundedBorderTextFieldStyle())
                .frame(width: 200)
                .onSubmit {
                    if !categoryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                        onSave()
                    }
                }
            
            HStack(spacing: 12) {
                Button("Cancel", action: onCancel)
                    .keyboardShortcut(.escape)
                
                Button(isNewCategory ? "Create" : "Save", action: onSave)
                    .keyboardShortcut(.return)
                    .disabled(categoryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding()
        .frame(width: 250, height: 120)
    }
}

struct LibraryCategoriesEditView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            LibraryCategoriesEditView()
        }
    }
}

