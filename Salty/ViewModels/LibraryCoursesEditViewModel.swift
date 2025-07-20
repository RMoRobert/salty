//
//  LibraryCoursesEditViewModel.swift
//  Salty
//
//  Created by Assistant on 1/27/25.
//

import Foundation
import SwiftUI
import SharingGRDB

@MainActor
class LibraryCoursesEditViewModel: ObservableObject {
    @Dependency(\.defaultDatabase) private var database
    
    // List view state
    @Published var selectedIndices: Set<Int> = []
    @Published var showingNewCourseAlert = false
    @Published var newCourseName = ""
    @Published var showingDuplicateNameAlert = false
    @Published var showingEditCourseAlert = false
    @Published var editingCourseName = ""
    @Published var editingCourseIndex: Int? = nil
    @Published var scrollToNewItem: Bool = false
    
    @FetchAll(#sql("SELECT \(Course.columns) FROM \(Course.self) ORDER BY \(Course.name) COLLATE NOCASE"))
    var courses: [Course]
    
    // MARK: - List View Methods
    
    func deleteCourse(at index: Int) {
        guard index < courses.count else { return }
        let courseToDelete = courses[index]
        
        do {
            try database.write { db in
                // Update recipes that reference this course to have no course
                try Recipe
                    .filter(Column("courseId") == courseToDelete.id)
                    .updateAll(db, Column("courseId").set(to: nil))
                
                // Then delete the course itself
                try courseToDelete.delete(db)
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
            print("Error deleting course: \(error)")
        }
    }
    
    func deleteSelectedCourses() {
        for index in selectedIndices.sorted(by: >) {
            deleteCourse(at: index)
        }
    }
    
    func showEditAlert() {
        if let firstSelectedIndex = selectedIndices.min(), firstSelectedIndex < courses.count {
            editingCourseName = courses[firstSelectedIndex].name
            editingCourseIndex = firstSelectedIndex
            showingEditCourseAlert = true
        }
    }
    
    func showNewCourseAlert() {
        newCourseName = ""
        showingNewCourseAlert = true
    }
    
    func createNewCourse() {
        let trimmedName = newCourseName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        
        do {
            // Check if a course with this name already exists (case-insensitive)
            let existingCourse = try database.read { db in
                try Course
                    .filter(sql: "LOWER(name) = LOWER(?)", arguments: [trimmedName])
                    .fetchOne(db)
            }
            
            if existingCourse != nil {
                // Show duplicate name error
                showingDuplicateNameAlert = true
                return
            }
            
            // Create the new course
            let newCourse = Course(id: UUID().uuidString, name: trimmedName)
            try database.write { db in
                try newCourse.insert(db)
            }
            
            // Select the new course and scroll to it
            selectedIndices = [courses.count - 1]
            scrollToNewItem = true
            newCourseName = ""
        } catch {
            print("Error creating course: \(error)")
        }
    }
    
    func updateCourseName(at index: Int, to newName: String) {
        guard index < courses.count else { return }
        let trimmedName = newName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        
        do {
            // Check if a course with this name already exists (case-insensitive)
            let existingCourse = try database.read { db in
                try Course
                    .filter(sql: "LOWER(name) = LOWER(?) AND id != ?", arguments: [trimmedName, courses[index].id])
                    .fetchOne(db)
            }
            
            if existingCourse != nil {
                // Show duplicate name error
                showingDuplicateNameAlert = true
                return
            }
            
            // Update the course name
            var updatedCourse = courses[index]
            updatedCourse.name = trimmedName
            try database.write { db in
                try updatedCourse.update(db)
            }
            
            editingCourseIndex = nil
            editingCourseName = ""
        } catch {
            print("Error updating course: \(error)")
        }
    }
    
    func clearNewCourseForm() {
        newCourseName = ""
    }
    
    func clearEditCourseForm() {
        editingCourseName = ""
        editingCourseIndex = nil
    }
    
    // MARK: - Computed Properties
    
    var canEdit: Bool {
        selectedIndices.count == 1
    }
    
    var canDelete: Bool {
        !selectedIndices.isEmpty
    }
    
    var canCreateNewCourse: Bool {
        !newCourseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
    
    var canSaveEdit: Bool {
        !editingCourseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }
} 