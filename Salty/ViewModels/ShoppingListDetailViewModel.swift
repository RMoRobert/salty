//
//  ShoppingListDetailViewModel.swift
//  Salty
//
//  Created by Robert on 7/24/26.
//

import Foundation
import OSLog
import SQLiteData
import UUIDV7

/// Backs the checklist view for one shopping list. Items are edited in memory (so inline TextFields
/// don't fight a reactive fetch) and persisted with a short debounce; the view is recreated per list
/// via `.id(listId)`, so `load()` runs once per selection.
@Observable
@MainActor
class ShoppingListDetailViewModel {
    private let logger = Logger(subsystem: "Salty", category: "Database")

    @ObservationIgnored
    @Dependency(\.defaultDatabase)
    private var database

    let listId: String
    var items: [ShoppingListListContents] = []
    var isLoaded = false

    @ObservationIgnored
    private var saveTask: Task<Void, Never>?

    init(listId: String) {
        self.listId = listId
    }

    var completedCount: Int { items.count { $0.isCompleted ?? false } }
    var hasCompletedItems: Bool { completedCount > 0 }

    /// Loads the checklist items. This view model only ever backs a structured list (the content
    /// column routes freeform lists to `ShoppingListFreeformView` instead), so there's no conversion
    /// here. List type is fixed at creation.
    func load() async {
        guard !isLoaded else { return }
        do {
            let list = try await database.read { [listId] db in
                try ShoppingList.where { $0.id.eq(listId) }.fetchOne(db)
            }
            guard let list else { return }
            items = list.contentsForList
            isLoaded = true
        } catch {
            logger.error("Error loading shopping list \(self.listId): \(error)")
        }
    }

    // MARK: - Item operations (each persists)

    /// Inserts a new empty item after the given one (or at the end) and returns its id for focusing.
    @discardableResult
    func addItem(after id: String? = nil, isHeading: Bool = false) -> String {
        let newItem = ShoppingListListContents(id: UUIDV7().uuidString, isHeading: isHeading, text: "")
        items.insert(newItem, at: items.insertionIndex(after: id))
        schedulePersist()
        return newItem.id
    }

    func toggleCompleted(id: String) {
        items.toggleCompleted(id: id)
        schedulePersist()
    }

    func toggleImportant(id: String) {
        items.toggleImportant(id: id)
        schedulePersist()
    }

    func updateText(id: String, text: String) {
        items.updateText(id: id, text: text)
        schedulePersist()
    }

    func deleteItem(id: String) {
        items.removeAll { $0.id == id }
        schedulePersist()
    }

    func deleteItems(atOffsets offsets: IndexSet) {
        items.remove(atOffsets: offsets)
        schedulePersist()
    }

    func moveItems(fromOffsets source: IndexSet, toOffset destination: Int) {
        items.move(fromOffsets: source, toOffset: destination)
        schedulePersist()
    }

    func clearCompleted() {
        items.clearCompleted()
        schedulePersist()
    }

    func uncheckAll() {
        items.uncheckAll()
        schedulePersist()
    }

    /// Drops empty rows (blank items left behind by inline editing). Called when the view goes away.
    func removeEmptyItems() {
        let cleaned = items.filter { !$0.text.trimmingCharacters(in: .whitespaces).isEmpty }
        if cleaned.count != items.count {
            items = cleaned
            schedulePersist()
        }
    }

    // MARK: - Persistence

    /// Debounced save: rapid edits (typing, repeated toggles) collapse into one write of the whole
    /// item array. `flush()` forces any pending save through (e.g. on disappear).
    private func schedulePersist() {
        saveTask?.cancel()
        saveTask = Task { [weak self] in
            try? await Task.sleep(for: .seconds(0.4))
            guard !Task.isCancelled else { return }
            self?.persistNow()
        }
    }

    func flush() {
        if saveTask != nil {
            saveTask?.cancel()
            saveTask = nil
            persistNow()
        }
    }

    private func persistNow() {
        saveTask = nil
        guard isLoaded else { return }
        let itemsToSave = items
        let id = listId
        let log = logger
        Task {
            do {
                try await database.write { db in
                    if var list = try ShoppingList.where { $0.id.eq(id) }.fetchOne(db) {
                        // Write only the checklist payload — never touch `isFreeform`. The kind is owned
                        // by creation and `convertToFreeform()`; a save that flipped it could undo a
                        // conversion via a late debounced write after the view has already swapped.
                        list.contentsForList = itemsToSave
                        list.lastModifiedDate = Date()
                        try ShoppingList.update(list).execute(db)
                    }
                }
            } catch {
                log.error("Error saving shopping list \(id): \(error)")
            }
        }
    }

    /// Converts this checklist into a freeform (Markdown-style) list: serializes the current items to
    /// text, flips `isFreeform`, and writes both. The content column then re-routes to the freeform
    /// editor. One-way — item stars aren't represented in the text form and are dropped. Pending
    /// checklist saves are cancelled first so none lands after the flip.
    func convertToFreeform() {
        saveTask?.cancel()
        saveTask = nil
        let content = ShoppingListFreeformConverter.text(from: items)
        let id = listId
        let log = logger
        Task {
            do {
                try await database.write { db in
                    if var list = try ShoppingList.where { $0.id.eq(id) }.fetchOne(db) {
                        list.isFreeform = true
                        list.contentsForFreeform = content
                        list.lastModifiedDate = Date()
                        try ShoppingList.update(list).execute(db)
                    }
                }
            } catch {
                log.error("Error converting shopping list \(id) to freeform: \(error)")
            }
        }
    }
}
