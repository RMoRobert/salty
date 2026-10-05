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

/// Backs the checklist view for one shopping list.
///
/// Items are edited in memory (so inline TextFields don't fight a reactive fetch) and the whole
/// array is written back on a short debounce. The stored row is observed alongside: a write this
/// editor didn't make -- a recipe's "Add to Shopping List" sheet, a sync download, the same list
/// open in another window -- replaces the in-memory items instead of being saved over. Each save
/// also names the stamp it expects the row to carry, and `ShoppingListWriter` refuses when the row
/// moved on in between; the observation then brings the newer row in.
///
/// The view is recreated per list via `.id(listId)`, so `load()` runs once per selection.
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

    /// The row as the database holds it, kept live. The view watches it and hands every change to
    /// `storedRowDidChange(to:)`; after `load()` nothing here reads it directly.
    @ObservationIgnored
    @FetchOne var storedRow: ShoppingList?

    /// The stamp of the row as this editor last loaded, observed or wrote it: what the next save
    /// expects to find, and how a change notification is told from a repeat.
    @ObservationIgnored
    private var storedStamp: ShoppingListStamp?

    /// The items the most recent write carried, so its own change notification is recognised
    /// rather than mistaken for an outside edit.
    @ObservationIgnored
    private var writtenItems: [ShoppingListListContents]?

    @ObservationIgnored
    private var saveTask: Task<Void, Never>?
    /// The database write in flight (or the last one started). Writes queue behind one another.
    @ObservationIgnored
    private var writeTask: Task<Void, Never>?

    /// How long a burst of edits settles before it is written. Injectable for tests.
    @ObservationIgnored
    private let debounce: Duration

    init(listId: String, debounce: Duration = .seconds(0.4)) {
        self.listId = listId
        self.debounce = debounce
        _storedRow = FetchOne(
            wrappedValue: nil as ShoppingList?,
            #sql("SELECT \(ShoppingList.columns) FROM \(ShoppingList.self) WHERE \(ShoppingList.id) = \(bind: listId)")
        )
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
                try await $storedRow.load()
                // Re-check after the suspension — two overlapping loads (double onAppear) both pass
                // the top guard, and the second to land would overwrite edits made since the first.
                guard !isLoaded else { return }
                // A missing row is a legitimately empty checklist.
                let row = storedRow
                items = row?.contentsForList ?? []
                storedStamp = ShoppingListStamp(lastModifiedDate: row?.lastModifiedDate)
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

    /// Takes in a change to the stored row. The view calls this whenever `storedRow` changes.
    ///
    /// This editor's own writes come back through here too, and are recognised by their contents.
    /// Anything else is an outside write, and replaces the items: a save still sitting in the
    /// debounce is dropped rather than flushed, because the outside write already built on what was
    /// stored and replaying this older array over it would erase its additions. The cost is at most
    /// the last fraction of a second of typing, which beats silently losing everything that was just
    /// added.
    func storedRowDidChange(to row: ShoppingList?) {
        guard isLoaded else { return }   // `load()` takes the row itself.
        let stamp = ShoppingListStamp(lastModifiedDate: row?.lastModifiedDate)
        guard stamp != storedStamp else { return }   // A repeat, or a write already accounted for.
        storedStamp = stamp
        let stored = row?.contentsForList ?? []
        if stored == items || stored == writtenItems {
            // Our own write landing before its completion was recorded, or a change to a column this
            // editor doesn't show (a rename, a conversion in another window): nothing to reload.
            return
        }
        saveTask?.cancel()
        saveTask = nil
        writeTask?.cancel()
        writeTask = nil
        writtenItems = nil
        items = stored
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
        saveTask = Task { [weak self, debounce] in
            try? await Task.sleep(for: debounce)
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

    /// Waits for a pending save and the write behind it to finish. For tests.
    func settle() async {
        await saveTask?.value
        await writeTask?.value
    }

    private func persistNow() {
        saveTask = nil
        guard isLoaded else { return }
        let itemsToSave = items
        let id = listId
        let log = logger
        // Each write waits for the one before it rather than cancelling it: the earlier write may
        // already have committed, and a save that didn't wait for its stamp to be recorded would
        // expect the old one and be refused. Only an outside change cancels (`storedRowDidChange`).
        let previous = writeTask
        writeTask = Task {
            await previous?.value
            guard !Task.isCancelled else { return }
            writtenItems = itemsToSave
            let expected = storedStamp
            do {
                let written = try await database.write { db in
                    // Write only the checklist payload — never touch `isFreeform`. The kind is owned
                    // by creation and `convertToFreeform()`; a save that flipped it could undo a
                    // conversion via a late debounced write after the view has already swapped.
                    try ShoppingListWriter.update(id: id, in: db, expecting: expected) { list in
                        list.contentsForList = itemsToSave
                    }
                }
                if let written {
                    storedStamp = ShoppingListStamp(of: written)
                }
            } catch is CancellationError {
                // Superseded by an outside change, which has already taken what is stored.
            } catch ShoppingListWriterError.modifiedElsewhere {
                // The row moved on under this editor; these items were built on the old one. The
                // observation delivers the newer row, and the edit is dropped as above.
                log.info("Dropped a stale save of shopping list \(id): it was changed elsewhere")
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
        let previous = writeTask
        writeTask = Task {
            await previous?.value
            guard !Task.isCancelled else { return }
            let expected = storedStamp
            do {
                let written = try await database.write { db in
                    try ShoppingListWriter.update(id: id, in: db, expecting: expected) { list in
                        list.isFreeform = true
                        list.contentsForFreeform = content
                    }
                }
                if let written {
                    storedStamp = ShoppingListStamp(of: written)
                }
            } catch ShoppingListWriterError.modifiedElsewhere {
                // The text was built from items that are no longer what's stored. The observation
                // brings the newer items in; the user can convert again from those.
                log.info("Dropped a conversion of shopping list \(id): it was changed elsewhere")
            } catch {
                log.error("Error converting shopping list \(id) to freeform: \(error)")
            }
        }
    }
}
