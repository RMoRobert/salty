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
import SaltyCore

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
    /// See the matching note in `ShoppingListFreeformViewModel.load()`: a `.task` cancelled during a
    /// navigation push used to leave `isLoaded` false forever, since nothing re-runs `.task`. Here that
    /// showed as a checklist stuck on neither its rows nor its empty state. Retry when our own task is
    /// still alive, and never finish in a state that waits indefinitely.
    func load() async {
        guard !isLoaded else { return }
        for _ in 0..<3 {
            do {
                let list = try await database.read { [listId] db in
                    try ShoppingList.where { $0.id.eq(listId) }.fetchOne(db)
                }
                // Re-check after the suspension — two overlapping loads (double onAppear) both pass
                // the top guard, and the second to land would overwrite edits made since the first.
                guard !isLoaded else { return }
                // A missing row is a legitimately empty checklist.
                items = list?.contentsForList ?? []
                isLoaded = true
                return
            } catch is CancellationError {
                if Task.isCancelled { return }
                continue
            } catch {
                logger.error("Error loading shopping list \(self.listId): \(error)")
                isLoaded = true
                return
            }
        }
    }

    /// Re-reads the checklist after the row was written by something other than this view model --
    /// today that's a recipe's "Add to Shopping List" sheet, which can land while this list is open
    /// in another window.
    ///
    /// A save still sitting in the debounce is dropped rather than flushed: the external write
    /// already added to what was stored, so replaying this older array over it would erase the
    /// additions. The cost is at most the last fraction of a second of typing, which beats silently
    /// losing everything that was just added.
    func reloadAfterExternalChange() async {
        guard isLoaded else { return }
        saveTask?.cancel()
        saveTask = nil
        do {
            let list = try await database.read { [listId] db in
                try ShoppingList.where { $0.id.eq(listId) }.fetchOne(db)
            }
            items = list?.contentsForList ?? []
        } catch {
            logger.error("Error reloading shopping list \(self.listId): \(error)")
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

    /// Removes the given row if the user never typed into it — called when focus leaves a row, so a
    /// blank draft disappears instead of lingering as an empty line (the Reminders behavior).
    func removeIfBlank(id: String) {
        if items.removeBlank(id: id) {
            schedulePersist()
        }
    }

    /// Drops all blank rows left behind by inline editing. Backstop for the paths focus tracking
    /// can't see: view disappearing mid-edit, and clearing stale drafts before inserting a new row.
    func removeEmptyItems() {
        if items.removeAllBlank() {
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
    /// editor. One-way — the `isImportant` flag (not currently UI-exposed) has no text form and is
    /// dropped. Pending checklist saves are cancelled first so none lands after the flip.
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
