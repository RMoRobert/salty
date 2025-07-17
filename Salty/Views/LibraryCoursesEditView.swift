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
    @FetchAll(Course.order(by: \.name)) private var courses
    @State private var selectedCourseIDs: Set<String> = []
    @State private var navigationPath = NavigationPath()
    
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack(path: $navigationPath) {
            List(selection: $selectedCourseIDs) {
                ForEach(courses, id: \.id) { course in
                    NavigationLink(value: course) {
                        HStack {
                            Text(course.name)
                        }
                    }
                }
            }
            .navigationTitle("Courses")
            .navigationDestination(for: Course.self) { course in
                LibraryCourseEditView(course: course) {
                    // Navigate back after saving
                    navigationPath.removeLast()
                }
            }
            .navigationDestination(for: CourseEditMode.self) { mode in
                LibraryCourseEditView(mode: mode) {
                    // Navigate back after creating
                    navigationPath.removeLast()
                }
            }
            #if os(macOS)
            .onDeleteCommand {
                deleteSelectedCourses()
            }
            #endif
            .padding()
            .frame(minWidth: 300, minHeight: 400)
            .toolbar {
                ToolbarItem {
                    Button(action: {
                        createNewCourse()
                    }) {
                        Image(systemName: "plus")
                    }
                }
                
                ToolbarItem {
                    Button(role: .destructive, action: {
                        deleteSelectedCourses()
                    }) {
                        Image(systemName: "minus")
                    }
                    .disabled(selectedCourseIDs.isEmpty)
                }
                
                ToolbarItem {
                    Button(action: {
                        editSelectedCourse()
                    }) {
                        Image(systemName: "pencil")
                    }
                    .disabled(selectedCourseIDs.count != 1)
                }
                
                ToolbarItem {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
    
    func deleteSelectedCourses() {
        try? database.write { db in
            for id in selectedCourseIDs {
                try Course.deleteOne(db, key: id)
            }
        }
        selectedCourseIDs.removeAll()
    }
    
    func createNewCourse() {
        navigationPath.append(CourseEditMode.new)
    }
    
    func editSelectedCourse() {
        guard selectedCourseIDs.count == 1,
              let selectedID = selectedCourseIDs.first,
              let course = courses.first(where: { $0.id == selectedID }) else {
            return
        }
        navigationPath.append(course)
    }
}

// MARK: - CourseEditMode
enum CourseEditMode: Hashable {
    case new
}

// MARK: - LibraryCourseEditView
struct LibraryCourseEditView: View {
    @Dependency(\.defaultDatabase) private var database
    @State private var courseName: String
    @State private var isNewCourse: Bool
    @State private var originalCourse: Course?
    
    let onSave: () -> Void
    
    // For editing existing course
    init(course: Course, onSave: @escaping () -> Void) {
        self._courseName = State(initialValue: course.name)
        self._isNewCourse = State(initialValue: false)
        self._originalCourse = State(initialValue: course)
        self.onSave = onSave
    }
    
    // For creating new course
    init(mode: CourseEditMode, onSave: @escaping () -> Void) {
        self._courseName = State(initialValue: "New Course")
        self._isNewCourse = State(initialValue: true)
        self._originalCourse = State(initialValue: nil)
        self.onSave = onSave
    }
    
    var body: some View {
        VStack(spacing: 20) {
            Text(isNewCourse ? "New Course" : "Edit Course")
                .font(.title2)
                .fontWeight(.semibold)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Name")
                    .font(.headline)
                
                TextField("Course name", text: $courseName)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .onSubmit {
                        saveCourse()
                    }
            }
            
            Spacer()
            
            HStack(spacing: 12) {
                Button("Cancel") {
                    onSave() // This will navigate back
                }
                .keyboardShortcut(.escape)
                
                Button(isNewCourse ? "Create" : "Save") {
                    saveCourse()
                }
                .keyboardShortcut(.return)
                .disabled(courseName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
                .buttonStyle(.borderedProminent)
            }
        }
        .padding()
        .frame(minWidth: 300, minHeight: 200)
        .navigationTitle(isNewCourse ? "New Course" : "Edit Course")
    }
    
    private func saveCourse() {
        let trimmedName = courseName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }
        
        try? database.write { db in
            if isNewCourse {
                // Create new course
                try Course.upsert(Course.Draft(id: UUID().uuidString, name: trimmedName))
                    .execute(db)
            } else if let course = originalCourse {
                // Update existing course
                var updatedCourse = course
                updatedCourse.name = trimmedName
                try updatedCourse.update(db)
            }
        }
        
        onSave()
    }
}

struct LibraryCoursesEditView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            LibraryCoursesEditView()
        }
    }
} 