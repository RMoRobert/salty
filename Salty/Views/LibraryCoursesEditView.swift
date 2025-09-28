//
//  LibraryCoursesEditView.swift
//  Salty
//
//  Created by Assistant on 1/27/25.
//

import Foundation
import SwiftUI

struct LibraryCoursesEditView: View {
    @StateObject private var viewModel = LibraryCoursesEditViewModel()
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        coursesList
            .navigationTitle("Edit Courses")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                #if !os(macOS)
                ToolbarItemGroup(placement: .bottomBar) {
                    HStack(spacing: 5) {
                        Button {
                            viewModel.showEditAlert()
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                        .disabled(!viewModel.canEdit)
                        
                        Button(role: .destructive) {
                            viewModel.deleteSelectedCourses()
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        .disabled(!viewModel.canDelete)
                    }
                    
                    Spacer()
                    
                    Button {
                        viewModel.showNewCourseAlert()
                    } label: {
                        Label("New", systemImage: "plus")
                    }
                    .labelStyle(.titleAndIcon)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
                #else
                ToolbarItem(placement: .automatic) {
                    Button(role: .destructive) {
                        viewModel.deleteSelectedCourses()
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .disabled(!viewModel.canDelete)
                }
                ToolbarItem(placement: .automatic) {
                    Button {
                        viewModel.showEditAlert()
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    .disabled(!viewModel.canEdit)
                }
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        viewModel.showNewCourseAlert()
                    } label: {
                        Label("New", systemImage: "plus")
                    }
                    .labelStyle(.titleAndIcon)
                }
                #endif
            }
            .alert("New Course", isPresented: $viewModel.showingNewCourseAlert) {
                TextField("Course Name", text: $viewModel.newCourseName)
                Button("Cancel", role: .cancel) {
                    viewModel.clearNewCourseForm()
                }
                Button("Add") {
                    viewModel.createNewCourse()
                }
                .disabled(!viewModel.canCreateNewCourse)
            } message: {
                Text("Enter a name for the new course")
            }
            .alert("Course Already Exists", isPresented: $viewModel.showingDuplicateNameAlert) {
                Button("OK") { }
            } message: {
                Text("A course with the name \"\(viewModel.newCourseName)\" already exists.")
            }
            .alert("Rename Course", isPresented: $viewModel.showingEditCourseAlert) {
                TextField("Course name", text: $viewModel.editingCourseName)
                Button("Cancel", role: .cancel) {
                    viewModel.clearEditCourseForm()
                }
                Button("Save") {
                    if let index = viewModel.editingCourseIndex {
                        viewModel.updateCourseName(at: index, to: viewModel.editingCourseName)
                    }
                }
                .disabled(!viewModel.canSaveEdit)
            } message: {
                Text("Enter the new name for the course")
            }
    }
    
    private var coursesList: some View {
        ScrollViewReader { proxy in
            List(selection: $viewModel.selectedIndices) {
                ForEach(Array(viewModel.courses.enumerated()), id: \.element.id) { index, course in
                    HStack {
                        Text(course.name)
                        Spacer()
                    }
                    .tag(index)
                    .id(index)
                }
                .onDelete { indexSet in
                    for index in indexSet.sorted(by: >) {
                        viewModel.deleteCourse(at: index)
                    }
                }
            }
            #if os(macOS)
            .listStyle(.bordered)
            .alternatingRowBackgrounds()
            #else
            .listStyle(.plain)
            #endif
            .onChange(of: viewModel.scrollToNewItem) { _, shouldScroll in
                if shouldScroll, let lastIndex = viewModel.courses.indices.last {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(lastIndex, anchor: .bottom)
                    }
                    viewModel.scrollToNewItem = false
                }
            }
        }
    }
}

struct LibraryCoursesEditView_Previews: PreviewProvider {
    static var previews: some View {
        LibraryCoursesEditView()
    }
} 
