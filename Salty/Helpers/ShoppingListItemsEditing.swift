//
//  ShoppingListItemsEditing.swift
//  Salty
//
//  Created by Robert on 7/24/26.
//

import Foundation

/// Pure array operations for checklist items, kept off the view model so they're unit-testable
/// (see ShoppingListItemsEditingTests). Array order IS the display/persisted order.
extension Array where Element == ShoppingListListContents {

    mutating func toggleCompleted(id: String) {
        guard let index = firstIndex(where: { $0.id == id }) else { return }
        self[index].isCompleted = !(self[index].isCompleted ?? false)
    }

    mutating func toggleImportant(id: String) {
        guard let index = firstIndex(where: { $0.id == id }) else { return }
        self[index].isImportant = !(self[index].isImportant ?? false)
    }

    mutating func updateText(id: String, text: String) {
        guard let index = firstIndex(where: { $0.id == id }) else { return }
        self[index].text = text
    }

    /// Removes completed items; headings are never completed, so they always survive.
    mutating func clearCompleted() {
        removeAll { $0.isCompleted ?? false }
    }

    mutating func uncheckAll() {
        for index in indices where self[index].isCompleted ?? false {
            self[index].isCompleted = false
        }
    }

    /// Where a new row inserted "after" the given item should land (end of the array when the
    /// anchor is nil or missing).
    func insertionIndex(after id: String?) -> Int {
        guard let id, let index = firstIndex(where: { $0.id == id }) else { return endIndex }
        return index + 1
    }
}
