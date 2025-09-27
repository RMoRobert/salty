//
//  LibraryTagsEditViewModel.swift
//  Salty
//
//  Created by Robert on 8/6/25.
//

import Foundation
import SwiftUI
import SQLiteData

@MainActor
@Observable
class LibraryTagsEditViewModel {
    @ObservationIgnored
    @Dependency(\.defaultDatabase) private var database
    
    // List view state
    var selectedIndices: Set<Int> = []
    var showingNewTagAlert = false
    var newTagName = ""
    var showingDuplicateNameAlert = false
    var showingEditTagAlert = false
    var editingTagName = ""
    var editingTagIndex: Int? = nil
    var scrollToNewItem: Bool = false
    var searchText: String = ""
    
    @ObservationIgnored
    @FetchAll(#sql("SELECT \(Tag.columns) FROM \(Tag.self) ORDER BY \(Tag.name) COLLATE NOCASE"))
    var tags: [Tag]
    
    // MARK: - List View Methods
    
    func updateQuery() async {
        do {
            if searchText.trim() == "" {
                try await $tags.load(
                    #sql(
                    """
                        SELECT \(Tag.columns) FROM \(Tag.self)
                        ORDER BY \(Tag.name) COLLATE NOCASE
                    """,
                    as: Tag.self)
                )
            }
            else {
                let searchPattern = "%\(searchText)%"
                try await $tags.load(
                    #sql(
                    """
                        SELECT \(Tag.columns) FROM \(Tag.self)
                        WHERE \(Tag.name) COLLATE NOCASE LIKE \(bind: searchPattern)
                        ORDER BY \(Tag.name) COLLATE NOCASE
                    """,
                    as: Tag.self)
                )
            }
        } catch {
          // Handle error...
        }
    }
    
    func deleteTag(at index: Int) {
        guard index < tags.count else { return }
        let tagToDelete = tags[index]
        
        do {
            try database.write { db in
                // Delete the tag (RecipeTag associations will be automatically removed due to cascade)
                try Tag.delete(tagToDelete).execute(db)
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
            print("Error deleting tag: \(error)")
        }
    }
    
    func deleteSelectedTags() {
        for index in selectedIndices.sorted(by: >) {
            deleteTag(at: index)
        }
    }
    
    func showEditAlert() {
        if let firstSelectedIndex = selectedIndices.min(), firstSelectedIndex < tags.count {
            editingTagName = tags[firstSelectedIndex].name
            editingTagIndex = firstSelectedIndex
            showingEditTagAlert = true
        }
    }
    
    func showNewTagAlert() {
        newTagName = ""
        showingNewTagAlert = true
    }
    
    func createNewTag() {
        let trimmedName = newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        
        do {
            // Check if a tag with this name already exists (case-insensitive)
            let existingTag = try database.read { db in
                try Tag
                    .where { $0.name.collate(.nocase) == trimmedName.collate(.nocase) }
                    .fetchOne(db)
            }
            
            if existingTag != nil {
                // Show duplicate name error
                showingDuplicateNameAlert = true
                return
            }
            
            // Create the new tag
            let newTag = Tag(id: UUID().uuidString, name: trimmedName)
            try database.write { db in
                try Tag.insert(newTag).execute(db)
            }
            
                         // Select the new tag and scroll to it
             selectedIndices = [tags.count - 1]
            scrollToNewItem = true
            newTagName = ""
        } catch {
            print("Error creating tag: \(error)")
        }
    }
    
    func updateTagName(at index: Int, to newName: String) {
        guard index < tags.count else { return }
        let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        
        do {
            // Check if a tag with this name already exists (case-insensitive)
            let existingTag = try database.read { db in
                try Tag
                    .where { $0.name.collate(.nocase) == trimmedName.collate(.nocase) && $0.id != tags[index].id }
                    .fetchOne(db)
            }
            
            if existingTag != nil {
                // Show duplicate name error
                showingDuplicateNameAlert = true
                return
            }
            
            // Update the tag name
            var updatedTag = tags[index]
            updatedTag.name = trimmedName
            try database.write { db in
                try Tag.update(updatedTag).execute(db)
            }
            
            editingTagIndex = nil
            editingTagName = ""
        } catch {
            print("Error updating tag: \(error)")
        }
    }
    
    func clearNewTagForm() {
        newTagName = ""
    }
    
    func clearEditTagForm() {
        editingTagName = ""
        editingTagIndex = nil
    }
    
    // MARK: - Computed Properties
    var canEdit: Bool {
        selectedIndices.count == 1
    }
    
    var canDelete: Bool {
        !selectedIndices.isEmpty
    }
    
    var canCreateNewTag: Bool {
        !newTagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    var canSaveEdit: Bool {
        !editingTagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
} 
