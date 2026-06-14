//
//  LibraryTagsEditView.swift
//  Salty
//
//  Created by Robert on 8/6/25.
//

import Foundation
import SwiftUI

struct LibraryTagsEditView: View {
    @State private var viewModel = LibraryTagsEditViewModel()
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        TagsListView(viewModel: viewModel)
            .navigationTitle("Edit Tags")
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
                            Task { await viewModel.deleteSelectedTags() }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        .disabled(!viewModel.canDelete)
                    }
                    
                    Spacer()
                    
                    Button {
                        viewModel.showNewTagAlert()
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
                        Task { await viewModel.deleteSelectedTags() }
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
                        viewModel.showNewTagAlert()
                    } label: {
                        Label("New", systemImage: "plus")
                    }
                    .labelStyle(.titleAndIcon)
                }
                #endif
            }
            .alert("New Tag", isPresented: $viewModel.showingNewTagAlert) {
                TextField("Tag Name", text: $viewModel.newTagName)
                Button("Cancel", role: .cancel) {
                    viewModel.clearNewTagForm()
                }
                Button("Add") {
                    Task { await viewModel.createNewTag() }
                }
                .disabled(!viewModel.canCreateNewTag)
            } message: {
                Text("Enter a name for the new tag")
            }
            .alert("Tag Already Exists", isPresented: $viewModel.showingDuplicateNameAlert) {
                Button("OK") { }
            } message: {
                Text("A tag with the name \"\(viewModel.newTagName)\" already exists.")
            }
            .alert("Rename Tag", isPresented: $viewModel.showingEditTagAlert) {
                TextField("Tag name", text: $viewModel.editingTagName)
                Button("Cancel", role: .cancel) {
                    viewModel.clearEditTagForm()
                }
                Button("Save") {
                    if let index = viewModel.editingTagIndex {
                        Task { await viewModel.updateTagName(at: index, to: viewModel.editingTagName) }
                    }
                }
                .disabled(!viewModel.canSaveEdit)
            } message: {
                Text("Enter the new name for the tag")
            }
    }
    
}

private struct TagsListView: View {
    @Bindable var viewModel: LibraryTagsEditViewModel

    var body: some View {
        ScrollViewReader { proxy in
            List(selection: $viewModel.selectedIndices) {
                ForEach(Array(viewModel.tags.enumerated()), id: \.element.id) { index, tag in
                    HStack {
                        Text(tag.name)
                        Spacer()
                    }
                    .tag(index)
                    .id(index)
                }
                .onDelete { indexSet in
                    Task {
                        for index in indexSet.sorted(by: >) {
                            await viewModel.deleteTag(at: index)
                        }
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
                if shouldScroll, let lastIndex = viewModel.tags.indices.last {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(lastIndex, anchor: .bottom)
                    }
                    viewModel.scrollToNewItem = false
                }
            }
            .searchable(text: $viewModel.searchText)
            .task(id: viewModel.searchText) {
                await viewModel.updateQuery()
            }
        }
    }
}

struct LibraryTagsEditView_Previews: PreviewProvider {
    static var previews: some View {
        LibraryTagsEditView()
    }
}
