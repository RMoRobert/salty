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
    @State private var selectedCourseID: String?
    @State private var originalSelectedCourseID: String?
    @State private var showingNewCourseAlert = false
    @State private var newCourseName = ""
    @State private var showingDuplicateNameAlert = false

    var body: some View {
        VStack(spacing: 20) {
            VStack(alignment: .leading, spacing: 12) {
                Text("Course")
                    .font(.headline)
                
                Picker("Course", selection: $selectedCourseID) {
                    Text("(No Course)")
                        .tag(nil as String?)
                    
                    ForEach(courses) { course in
                        Text(course.name)
                            .tag(course.id as String?)
                    }
                }
                #if os(macOS)
                .pickerStyle(.menu)
                .frame(maxWidth: .infinity, alignment: .leading)
                #else
                .pickerStyle(.wheel)
                #endif
            }
            
            Button(action: {
                newCourseName = ""
                showingNewCourseAlert = true
            }) {
                Label("Create New Course", systemImage: "plus.circle")
            }
            .foregroundColor(.accentColor)
            
            Spacer()
            
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
                .disabled(selectedCourseID == originalSelectedCourseID)
            }
            #endif
        }
        .padding()
        #if os(macOS)
        .frame(minWidth: 300, minHeight: 200)
        #endif
        #if !os(macOS)
        .navigationTitle("Course")
        .navigationBarTitleDisplayMode(.inline)
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
                .disabled(selectedCourseID == originalSelectedCourseID)
            }
        }
        #endif
        .onAppear {
            loadSelectedCourse()
        }
        .onChange(of: courses) { _, _ in
            loadSelectedCourse()
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
                // Refresh selected course when the sheet is dismissed
                loadSelectedCourse()
            }
        }
    }
    
    
    private func loadSelectedCourse() {
        selectedCourseID = recipe.courseId
        originalSelectedCourseID = recipe.courseId
    }
    
    private func saveChanges() {
        do {
            try database.write { db in
                // Update the recipe's courseId directly
                var updatedRecipe = recipe
                updatedRecipe.courseId = selectedCourseID
                updatedRecipe.lastModifiedDate = Date()
                try updatedRecipe.update(db)
                
                // Update the binding
                recipe = updatedRecipe
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
            
            // Select the new course (but don't save to database yet)
            selectedCourseID = newCourse.id
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
