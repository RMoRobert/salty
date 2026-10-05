//
//  CategoryEditView.swift
//  Salty
//
//  Created by Robert on 6/2/23.
//
//  A picker over the library's categories. It edits a copy of the selection it was given and hands
//  the copy back on Save; Cancel (or dismissing the popover) leaves the caller's selection alone.
//  The recipe editor holding that selection writes it when the recipe is saved.
//

import SwiftUI
import SaltyCore

struct CategoryEditView: View {
    @Binding var selectedCategoryIDs: Set<String>
    @State private var viewModel: CategoryEditViewModel
    @Environment(\.dismiss) private var dismiss

    init(selectedCategoryIDs: Binding<Set<String>>) {
        _selectedCategoryIDs = selectedCategoryIDs
        _viewModel = State(initialValue: CategoryEditViewModel(selectedCategoryIDs: selectedCategoryIDs.wrappedValue))
    }

    var body: some View {
        VStack {
            CategoryPickerList(viewModel: viewModel)

            #if os(macOS)
            CategoryPickerButtons(viewModel: viewModel, onCancel: { dismiss() }, onSave: save)
            #endif
        }
        .navigationTitle("Edit Categories")
        #if os(macOS)
        .padding([.top, .leading, .trailing])
        #else
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)
            }

            ToolbarItem(placement: .confirmationAction) {
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!viewModel.hasChanges)
            }
        }
        #endif
        .alert("New Category", isPresented: $viewModel.showingNewCategoryAlert) {
            TextField("Category Name", text: $viewModel.newCategoryName)
            Button("Cancel", role: .cancel) {
                viewModel.newCategoryName = ""
            }
            Button("Add") {
                Task { await viewModel.createNewCategory() }
            }
            .disabled(viewModel.newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("Enter a name for the new category")
        }
        .alert("Category Already Exists", isPresented: $viewModel.showingDuplicateNameAlert) {
            Button("OK") { }
        } message: {
            Text("A category with the name \"\(viewModel.newCategoryName)\" already exists.")
        }
    }

    private func save() {
        selectedCategoryIDs = viewModel.selectionToCommit
        dismiss()
    }
}

// MARK: - Supporting Views

private struct CategoryPickerList: View {
    @Bindable var viewModel: CategoryEditViewModel

    var body: some View {
        List {
            ForEach(viewModel.categories) { category in
                Toggle(category.name, isOn: Binding(
                    get: { viewModel.isSelected(category.id) },
                    set: { viewModel.setSelected(category.id, $0) }
                ))
            }

            Button("Create New Category", systemImage: "plus.circle") {
                viewModel.newCategoryName = ""
                viewModel.showingNewCategoryAlert = true
            }
            .foregroundStyle(Color.accentColor)
        }
        #if os(macOS)
        .frame(minWidth: 300, minHeight: 400)
        #else
        .frame(minWidth: 200, minHeight: 300)
        #endif
    }
}

#if os(macOS)
private struct CategoryPickerButtons: View {
    let viewModel: CategoryEditViewModel
    let onCancel: () -> Void
    let onSave: () -> Void

    var body: some View {
        HStack {
            Button("Cancel", action: onCancel)
                .keyboardShortcut(.cancelAction)

            Spacer()

            Button("Save", action: onSave)
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!viewModel.hasChanges)
        }
        .padding(.top, 4).padding(.bottom, 12)
    }
}
#endif

#Preview {
    @Previewable @State var selectedCategoryIDs = Set<String>()
    CategoryEditView(selectedCategoryIDs: $selectedCategoryIDs)
}
