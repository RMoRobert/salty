//
//  LibraryCategoriesEditView.swift
//  Salty
//
//  Created by Robert on 6/2/23.
//

import Foundation
import SwiftUI
import SharingGRDB

struct LibraryCategoriesEditView: View {
    @Dependency(\.defaultDatabase) private var database
    
    @FetchAll private var categories: [Category]
    
    @State private var selectedCategoryIDs: Set<String>? = nil
    
    @State private var editingCategory: Category? = nil
    
    @Environment(\.dismiss) var dismiss
    
    var body: some View {
        NavigationStack {
            List(categories, id: \.id, selection: $selectedCategoryIDs) { category in
                if editingCategory?.id == category.id {
                    TextField("Category Name", text: Binding(
                        get: { editingCategory?.name ?? "" },
                        set: { newValue in
                            if var editingCategory = editingCategory {
                                editingCategory.name = newValue
                                self.editingCategory = editingCategory
                            }
                        }
                    ))
                    .textFieldStyle(.roundedBorder)
                    .onSubmit {
                        saveEditingCategory()
                    }
                    .onExitCommand {
                        editingCategory = nil
                    }
                } else {
                    HStack {
                        Text(category.name)
                            #if os(macOS)
                            .onTapGesture(count: 2) {
                                editingCategory = category
                            }
                            #endif
                        Spacer()
                        Button(action: {
                            editingCategory = category
                        }) {
                            Image(systemName: "pencil")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                    }
                    .contextMenu {
                        Button(role: .destructive, action: { deleteCategory(id: category.id) } ) {
                            Text("Delete")
                        }
                    }
                }
            }
            .listStyle(.inset(alternatesRowBackgrounds: true))
            .contentShape(Rectangle())
            .onTapGesture {
                saveEditingCategory()
            }
        }
        .padding()
        .frame(minWidth: 300, minHeight: 400)
        .toolbar {
            ToolbarItem(placement: .automatic) {
                Button(action: {
                    try? database.write { db in
                        let category = Category(id: UUID().uuidString, name: "New Category")
                        try category.insert(db)
                        editingCategory = category
                    }
                }) {
                    Image(systemName: "plus")
                }
            }
            
            ToolbarItem(placement: .automatic) {
                Button(role: .destructive, action: {
                    deleteSelectedCategories()
                }) {
                    Image(systemName: "minus")
                }
                .disabled(selectedCategoryIDs?.isEmpty ?? true)
            }
            
            ToolbarItem(placement: .automatic) {
                Button("Done") {
                    saveEditingCategory()
                    dismiss()
                }
            }
        }
    }
    
    private func saveEditingCategory() {
        if let category = editingCategory {
            try? database.write { db in
                try category.update(db)
            }
        }
        editingCategory = nil
    }
    
    func deleteSelectedCategories() {
        guard let ids = selectedCategoryIDs else { return }
        try? database.write { db in
            for id in ids {
                try Category.deleteOne(db, key: id)
            }
        }
        selectedCategoryIDs?.removeAll()
    }
    
    func deleteCategory(id: String) {
        try? database.write { db in
            try Category.deleteOne(db, key: id)
        }
    }
}

struct LibraryCategoryEditView: View {
    @Dependency(\.defaultDatabase) private var database
    @State var category: Category
    
    var body: some View {
        VStack {
            TextField("Name", text: $category.name)
                .onChange(of: category.name) { _, newValue in
                    try? database.write { db in
                        try category.update(db)
                    }
                }
        }
        .padding()
    }
}

struct LibraryCategoriesEditView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            LibraryCategoriesEditView()
        }
    }
}

