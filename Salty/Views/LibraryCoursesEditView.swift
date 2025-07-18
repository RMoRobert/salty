//
//  LibraryCoursesEditView.swift
//  Salty
//
//  Created by Assistant on 1/27/25.
//

import Foundation
import SwiftUI
import SharingGRDB

struct LibraryCoursesEditView: View {
    @Dependency(\.defaultDatabase) private var database
    
    @FetchAll(#sql("SELECT \(Course.columns) FROM \(Course.self) ORDER BY \(Course.name) COLLATE NOCASE"))
    var courses: [Course]
    
    @State private var selectedIndices: Set<Int> = []
    @State private var showingNewCourseAlert = false
    @State private var newCourseName = ""
    @State private var showingDuplicateNameAlert = false
    @State private var showingEditCourseAlert = false
    @State private var editingCourseName = ""
    @State private var editingCourseIndex: Int? = nil
    @State private var scrollToNewItem: Bool = false
    
    @Environment(\.dismiss) var dismiss
    
    private func deleteCourse(at index: Int) {
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
    
    var body: some View {
        VStack {
            coursesList
            
            // Add, Edit, and Delete buttons
            HStack {
                Button {
                    newCourseName = ""
                    showingNewCourseAlert = true
                } label: {
                    #if !os(macOS)
                    Label("Add", systemImage: "plus").padding()
                    #else
                    Label("Add Course", systemImage: "plus")
                    #endif
                }
                .padding(.trailing)
                
                Button {
                    if let firstSelectedIndex = selectedIndices.min(), firstSelectedIndex < courses.count {
                        editingCourseName = courses[firstSelectedIndex].name
                        editingCourseIndex = firstSelectedIndex
                        showingEditCourseAlert = true
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
                        deleteCourse(at: index)
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
        .navigationTitle("Edit Courses")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    dismiss()
                }
            }
        }
        .padding()
        .alert("New Course", isPresented: $showingNewCourseAlert) {
            TextField("Course Name", text: $newCourseName)
            Button("Cancel", role: .cancel) {
                newCourseName = ""
            }
            Button("Add") {
                createNewCourse()
            }
            .disabled(newCourseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("Enter a name for the new course")
        }
        .alert("Course Already Exists", isPresented: $showingDuplicateNameAlert) {
            Button("OK") { }
        } message: {
            Text("A course with the name \"\(newCourseName)\" already exists.")
        }
        .alert("Rename Course", isPresented: $showingEditCourseAlert) {
            TextField("Course name", text: $editingCourseName)
            Button("Cancel", role: .cancel) {
                editingCourseName = ""
                editingCourseIndex = nil
            }
            Button("Save") {
                if let index = editingCourseIndex {
                    updateCourseName(at: index, to: editingCourseName)
                }
            }
            .disabled(editingCourseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("Enter the new name for the course")
        }
    }
    
    private func createNewCourse() {
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
    
    private func updateCourseName(at index: Int, to newName: String) {
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
    private var coursesList: some View {
        ScrollViewReader { proxy in
            List(selection: $selectedIndices) {
                ForEach(Array(courses.enumerated()), id: \.element.id) { index, course in
                    HStack {
                        Text(course.name)
                        Spacer()
                    }
                    .tag(index)
                    .id(index)
                }
                .onDelete { indexSet in
                    for index in indexSet.sorted(by: >) {
                        deleteCourse(at: index)
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
                if shouldScroll, let lastIndex = courses.indices.last {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(lastIndex, anchor: .bottom)
                    }
                    scrollToNewItem = false
                }
            }
        }
    }
}

// MARK: - CourseEditMode
enum CourseEditMode: Hashable {
    case new
}

// MARK: - LibraryCourseEditView


struct LibraryCoursesEditView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            LibraryCoursesEditView()
        }
    }
} 
