//
//  ShoppingListItemsEditing.swift
//  Salty
//
//  Created by Robert on 7/24/26.
//

import Foundation

extension ShoppingListListContents {
    /// True when the row has no visible text — the state of a row created by "New Item" that the
    /// user never typed into. Blank rows are transient: they only exist while being edited.
    public var isBlank: Bool {
        text.trimmingCharacters(in: .whitespaces).isEmpty
    }
}

/// Pure array operations for checklist items, kept off the view model so they're unit-testable
/// (see ShoppingListItemsEditingTests). Array order IS the display/persisted order.
extension Array where Element == ShoppingListListContents {

    public mutating func toggleCompleted(id: String) {
        guard let index = firstIndex(where: { $0.id == id }) else { return }
        self[index].isCompleted = !(self[index].isCompleted ?? false)
    }

    public mutating func toggleImportant(id: String) {
        guard let index = firstIndex(where: { $0.id == id }) else { return }
        self[index].isImportant = !(self[index].isImportant ?? false)
    }

    public mutating func updateText(id: String, text: String) {
        guard let index = firstIndex(where: { $0.id == id }) else { return }
        self[index].text = text
    }

    /// Removes completed items; headings are never completed, so they always survive.
    public mutating func clearCompleted() {
        removeAll { $0.isCompleted ?? false }
    }

    public mutating func uncheckAll() {
        for index in indices where self[index].isCompleted ?? false {
            self[index].isCompleted = false
        }
    }

    /// Where a new row inserted "after" the given item should land (end of the array when the
    /// anchor is nil or missing).
    public func insertionIndex(after id: String?) -> Int {
        guard let id, let index = firstIndex(where: { $0.id == id }) else { return endIndex }
        return index + 1
    }

    /// Removes the given row only if it's still blank — how a never-typed-into row vanishes when
    /// focus leaves it (the Reminders behavior). Returns true when a row was removed.
    @discardableResult
    public mutating func removeBlank(id: String) -> Bool {
        guard let index = firstIndex(where: { $0.id == id }), self[index].isBlank else { return false }
        remove(at: index)
        return true
    }

    /// Removes every blank row (items and headings alike). Returns true when anything was removed.
    @discardableResult
    public mutating func removeAllBlank() -> Bool {
        let countBefore = count
        removeAll(where: \.isBlank)
        return count != countBefore
    }
}
