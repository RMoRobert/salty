//
//  LibraryCategoriesEditViewModel.swift
//  Salty
//
//  Created by Robert on 6/2/23.
//

import Foundation
import SwiftUI
import SQLiteData

@MainActor
class LibraryCategoriesEditViewModel: ObservableObject {
    @Dependency(\.defaultDatabase) private var database
    
    // List view state
    @Published var selectedIndices: Set<Int> = []
    @Published var showingNewCategoryAlert = false
    @Published var newCategoryName = ""
    @Published var showingDuplicateNameAlert = false
    @Published var showingEditCategoryAlert = false
    @Published var editingCategoryName = ""
    @Published var editingCategoryIndex: Int? = nil
    @Published var scrollToNewItem: Bool = false
    
    @FetchAll(#sql("SELECT \(Category.columns) FROM \(Category.self) ORDER BY \(Category.name) COLLATE NOCASE"))
    var categories: [Category]
    
    // MARK: - List View Methods
    
    func deleteCategory(at index: Int) {
        guard index < categories.count else { return }
        let categoryToDelete = categories[index]
        
        do {
            try database.write { db in
                // Remove from recipe associations first
                try RecipeCategory
                    .where { $0.categoryId == categoryToDelete.id }
                    .delete()
                    .execute(db)
                
                // Then delete the category itself
                try Category.delete(categoryToDelete).execute(db)
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
    
    func deleteSelectedCategories() {
        for index in selectedIndices.sorted(by: >) {
            deleteCategory(at: index)
        }
    }
    
    func showEditAlert() {
        if let firstSelectedIndex = selectedIndices.min(), firstSelectedIndex < categories.count {
            editingCategoryName = categories[firstSelectedIndex].name
            editingCategoryIndex = firstSelectedIndex
            showingEditCategoryAlert = true
        }
    }
    
    func showNewCategoryAlert() {
        newCategoryName = ""
        showingNewCategoryAlert = true
    }
    
    func createNewCategory() {
        let trimmedName = newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        
        do {
            // Check if a category with this name already exists (case-insensitive)
            let existingCategory = try database.read { db in
                try Category
                    .where { $0.name.collate(.nocase) == trimmedName.collate(.nocase) }
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
                try Category.insert {
                    newCategory
                }.execute(db)
            }
            
            // Select the new category and scroll to it
            selectedIndices = [categories.count - 1]
            scrollToNewItem = true
            newCategoryName = ""
        } catch {
            print("Error creating category: \(error)")
        }
    }
    
    func updateCategoryName(at index: Int, to newName: String) {
        guard index < categories.count else { return }
        let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        
        do {
            // Check if a category with this name already exists (case-insensitive)
            let existingCategory = try database.read { db in
                try Category
                    .where { $0.name.collate(.nocase) == trimmedName.collate(.nocase) && $0.id != categories[index].id }
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
                try Category.update(updatedCategory).execute(db)
            }
            
            editingCategoryIndex = nil
            editingCategoryName = ""
        } catch {
            print("Error updating category: \(error)")
        }
    }
    
    func clearNewCategoryForm() {
        newCategoryName = ""
    }
    
    func clearEditCategoryForm() {
        editingCategoryName = ""
        editingCategoryIndex = nil
    }
    
    // MARK: - Computed Properties
    
    var canEdit: Bool {
        selectedIndices.count == 1
    }
    
    var canDelete: Bool {
        !selectedIndices.isEmpty
    }
    
    var canCreateNewCategory: Bool {
        !newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    var canSaveEdit: Bool {
        !editingCategoryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
} 
