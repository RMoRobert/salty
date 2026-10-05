//
//  CategoryEditViewModel.swift
//  Salty
//
//  The category picker's state: the library's categories, the selection being edited, and the one
//  write the picker makes itself -- creating a category -- which goes through the library's own
//  editor so the name is checked by the same duplicate rule as everywhere else.
//
//  The selection is a copy. The picker's Save hands it back to the recipe editor, which holds it
//  until the recipe is saved; its Cancel drops it. The picker itself never touches a recipe.
//

import Foundation
import OSLog
import SQLiteData
import SaltyCore

@Observable
@MainActor
final class CategoryEditViewModel {
    private let logger = Logger(subsystem: "Salty", category: "UI")

    @ObservationIgnored
    @Dependency(\.defaultDatabase) private var database

    @ObservationIgnored
    @FetchAll(#sql("SELECT \(Category.columns) FROM \(Category.self) ORDER BY \(Category.name) COLLATE NOCASE"))
    var categories: [Category]

    /// The selection as the picker shows it.
    var selectedCategoryIDs: Set<String>
    private let originalCategoryIDs: Set<String>

    var newCategoryName = ""
    var showingNewCategoryAlert = false
    var showingDuplicateNameAlert = false

    init(selectedCategoryIDs: Set<String>) {
        self.selectedCategoryIDs = selectedCategoryIDs
        self.originalCategoryIDs = selectedCategoryIDs
    }

    var hasChanges: Bool {
        selectedCategoryIDs != originalCategoryIDs
    }

    func isSelected(_ categoryID: String) -> Bool {
        selectedCategoryIDs.contains(categoryID)
    }

    func setSelected(_ categoryID: String, _ isSelected: Bool) {
        if isSelected {
            selectedCategoryIDs.insert(categoryID)
        } else {
            selectedCategoryIDs.remove(categoryID)
        }
    }

    /// What Save hands back: the selection less any category deleted (by a sync, or in another
    /// window) while the picker was open.
    var selectionToCommit: Set<String> {
        selectedCategoryIDs.intersection(categories.map(\.id))
    }

    /// Creates the category named in `newCategoryName` and selects it, or reports a duplicate.
    func createNewCategory() async {
        let trimmedName = newCategoryName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        do {
            // One write: the library's own duplicate rule (case, surrounding and internal whitespace)
            // decides whether the name is taken, and the classifier editor stamps the new row like
            // every other library write.
            let createdId: String? = try await database.write { db in
                if try LibraryClassifierEditor.existingRow(classifier: .category, name: trimmedName, in: db) != nil {
                    return nil
                }
                return try LibraryClassifierEditor.create(classifier: .category, name: trimmedName, in: db)
            }

            guard let createdId else {
                showingDuplicateNameAlert = true
                return
            }

            selectedCategoryIDs.insert(createdId)
            newCategoryName = ""
        } catch {
            logger.error("Error creating category: \(error)")
        }
    }
}
