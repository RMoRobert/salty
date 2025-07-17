//
//  CourseEditView.swift
//  Salty
//
//  Created by Robert on 7/16/25.
//

import SwiftUI
import SharingGRDB

struct CourseEditView: View {
    @Dependency(\.defaultDatabase) private var database
    @Binding var recipe: Recipe
    @Environment(\.dismiss) private var dismiss
    
    @FetchAll(Course.order(by: \.name)) private var courses
    
    @State private var showingEditLibraryCoursesSheet = false
    @State private var selectedCourseIDs: Set<String> = []
    @State private var originalSelectedCourseIDs: Set<String> = []
    @State private var showingNewCourseAlert = false
    @State private var newCourseName = ""
    @State private var showingDuplicateNameAlert = false

    var body: some View {
        VStack {
            List {
                ForEach(courses) { course in
                    Toggle(course.name, isOn: Binding<Bool> (
                        get: {
                            selectedCourseIDs.contains(course.id)
                        },
                        set: { newVal in
                            if newVal {
                                selectedCourseIDs.insert(course.id)
                            } else {
                                selectedCourseIDs.remove(course.id)
                            }
                        }
                    ))
                }
                
                Button(action: {
                    newCourseName = ""
                    showingNewCourseAlert = true
                }) {
                    Label("Create New Course", systemImage: "plus.circle")
                }
                .foregroundColor(.accentColor)
            }
            #if os(macOS)
            .frame(minWidth: 300, minHeight: 400)
            #else
            .frame(minWidth: 200, minHeight: 300)
            #endif
            
            #if os(macOS)
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
                .disabled(selectedCourseIDs == originalSelectedCourseIDs)
            }
            .padding(.top, 4).padding(.bottom, 12)
            #endif
        }
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
                .disabled(selectedCourseIDs == originalSelectedCourseIDs)
            }
        }
        #endif
        .onAppear {
            loadSelectedCourses()
        }
        .onChange(of: courses) { _, _ in
            loadSelectedCourses()
        }
        .sheet(isPresented: $showingEditLibraryCoursesSheet) {
            LibraryCoursesEditView()
        }
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
        .onChange(of: showingEditLibraryCoursesSheet) { _, isPresented in
            if !isPresented {
                // Refresh selected courses when the sheet is dismissed
                loadSelectedCourses()
            }
        }
    }
    
    
    private func loadSelectedCourses() {
        do {
            let selectedIDs = try database.read { db in
                try RecipeCourse
                    .filter(Column("recipeId") == recipe.id)
                    .fetchAll(db)
                    .map { $0.courseId }
            }
            selectedCourseIDs = Set(selectedIDs)
            originalSelectedCourseIDs = Set(selectedIDs)
        } catch {
            selectedCourseIDs = []
            originalSelectedCourseIDs = []
        }
    }
    
    private func saveChanges() {
        do {
            try database.write { db in
                // Remove courses that are no longer selected
                let coursesToRemove = originalSelectedCourseIDs.subtracting(selectedCourseIDs)
                for courseId in coursesToRemove {
                    try RecipeCourse
                        .filter(Column("recipeId") == recipe.id && Column("courseId") == courseId)
                        .deleteAll(db)
                }
                
                // Add newly selected courses
                let coursesToAdd = selectedCourseIDs.subtracting(originalSelectedCourseIDs)
                for courseId in coursesToAdd {
                    let recipeCourse = RecipeCourse(recipeId: recipe.id, courseId: courseId)
                    try recipeCourse.insert(db)
                }
            }
        } catch {
            print("Error saving course changes: \(error)")
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
            
            // Add to selected courses (but don't save to database yet)
            selectedCourseIDs.insert(newCourse.id)
            newCourseName = ""
        } catch {
            // Handle error - could add error alert here if needed
            print("Error creating course: \(error)")
        }
    }
}

#Preview {
    @Previewable @State var recipe = SampleData.sampleRecipes[0]
    CourseEditView(recipe: $recipe)
} 
