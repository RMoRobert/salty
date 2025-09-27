//
//  LibraryCategoriesEditView.swift
//  Salty
//
//  Created by Robert on 6/2/23.
//

import Foundation
import SwiftUI
import SQLiteData

struct LibraryCategoriesEditView: View {
    @StateObject private var viewModel = LibraryCategoriesEditViewModel()
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        categoriesList
            .navigationTitle("Edit Categories")
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
                            viewModel.deleteSelectedCategories()
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        .disabled(!viewModel.canDelete)
                    }
                    
                    Spacer()
                    
                    Button {
                        viewModel.showNewCategoryAlert()
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
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        viewModel.showNewCategoryAlert()
                    } label: {
                        Label("New", systemImage: "plus")
                    }
                    .labelStyle(.titleAndIcon)
                }
                ToolbarItem(placement: .secondaryAction) {
                    Button(role: .destructive) {
                        viewModel.deleteSelectedCategories()
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    //.labelStyle(.titleAndIcon)
                    .disabled(!viewModel.canDelete)
                }
                ToolbarItem(placement: .secondaryAction) {
                    Button {
                        viewModel.showEditAlert()
                    } label: {
                        Label("Edit", systemImage: "pencil")
                    }
                    //.labelStyle(.titleAndIcon)
                    .disabled(!viewModel.canEdit)
                }
                #endif
            }
            .alert("New Category", isPresented: $viewModel.showingNewCategoryAlert) {
                TextField("Category Name", text: $viewModel.newCategoryName)
                Button("Cancel", role: .cancel) {
                    viewModel.clearNewCategoryForm()
                }
                Button("Add") {
                    viewModel.createNewCategory()
                }
                .disabled(!viewModel.canCreateNewCategory)
            } message: {
                Text("Enter a name for the new category")
            }
            .alert("Category Already Exists", isPresented: $viewModel.showingDuplicateNameAlert) {
                Button("OK") { }
            } message: {
                Text("A category with the name \"\(viewModel.newCategoryName)\" already exists.")
            }
            .alert("Rename Category", isPresented: $viewModel.showingEditCategoryAlert) {
                TextField("Category name", text: $viewModel.editingCategoryName)
                Button("Cancel", role: .cancel) {
                    viewModel.clearEditCategoryForm()
                }
                Button("Save") {
                    if let index = viewModel.editingCategoryIndex {
                        viewModel.updateCategoryName(at: index, to: viewModel.editingCategoryName)
                    }
                }
                .disabled(!viewModel.canSaveEdit)
            } message: {
                Text("Enter the new name for the category")
            }
    }
    
    private var categoriesList: some View {
        ScrollViewReader { proxy in
            List(selection: $viewModel.selectedIndices) {
                ForEach(Array(viewModel.categories.enumerated()), id: \.element.id) { index, category in
                    HStack {
                        Text(category.name)
                        Spacer()
                    }
                    .tag(index)
                    .id(index)
                }
                .onDelete { indexSet in
                    for index in indexSet.sorted(by: >) {
                        viewModel.deleteCategory(at: index)
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
                if shouldScroll, let lastIndex = viewModel.categories.indices.last {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(lastIndex, anchor: .bottom)
                    }
                    viewModel.scrollToNewItem = false
                }
            }
        }
    }
}

struct LibraryCategoriesEditView_Previews: PreviewProvider {
    static var previews: some View {
        LibraryCategoriesEditView()
    }
}

