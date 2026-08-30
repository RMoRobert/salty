//
//  ShoppingListFreeformViewModel.swift
//  Salty
//
//  Created by Robert on 7/24/26.
//

import Foundation
import OSLog
import SQLiteData
import SaltyCore

/// Backs the freeform (Markdown-style) editor for one shopping list. Mirrors the debounced-save
/// pattern of `ShoppingListDetailViewModel`, but the payload is a single text blob
/// (`contentsForFreeform`). The view is recreated per list via `.id(...)`, so `load()` runs once.
@Observable
@MainActor
class ShoppingListFreeformViewModel {
    private let logger = Logger(subsystem: "Salty", category: "Database")

    @ObservationIgnored
    @Dependency(\.defaultDatabase)
    private var database

    let listId: String
    var text = ""
    var isLoaded = false

    /// Identifies this editor to `ShoppingListChangeNotifier`, so the saves it announces reach every
    /// other editor of this list and not itself. See `ShoppingListDetailViewModel.editorToken`.
    let editorToken = UUID()

    @ObservationIgnored
    private var saveTask: Task<Void, Never>?

    init(listId: String) {
        self.listId = listId
    }

    /// Loads the list text.
    ///
    /// The retry matters: `.task` is cancelled when the view goes away, and during a navigation push
    /// SwiftUI can cancel the read out from under a view that then *stays* on screen. Treating that
    /// `CancellationError` as a failure left `isLoaded` false and `text` empty forever — nothing
    /// re-runs `.task` — which is what made the preview come up blank until the Edit/Preview picker
    /// was toggled. So: if our own task is still alive, the cancellation was spurious — try again.
    func load() async {
        guard !isLoaded else { return }
        for _ in 0..<3 {
            do {
                let list = try await database.read { [listId] db in
                    try ShoppingList.where { $0.id.eq(listId) }.fetchOne(db)
                }
                // Re-check after the suspension: onAppear can fire twice in quick succession, and two
                // in-flight loads both pass the guard at the top. Without this, whichever lands SECOND
                // would overwrite `text` — including any keystrokes typed since the first landed.
                guard !isLoaded else { return }
                // A missing row is a legitimately empty document, not a reason to keep waiting.
                text = list?.contentsForFreeform ?? ""
                isLoaded = true
                return
            } catch is CancellationError {
                // Largely vestigial now that the caller uses an unstructured Task (nothing cancels
                // it), but kept as defense if load() is ever called from a cancellable context again:
                // spurious cancellation → retry; real cancellation → bail, and the next onAppear
                // re-runs load() with `isLoaded` still false, so nothing is lost.
                if Task.isCancelled { return }
                continue
            } catch {
                logger.error("Error loading shopping list \(self.listId): \(error)")
                // Show an empty editor rather than an indefinite placeholder.
                isLoaded = true
                return
            }
        }
    }

    /// Re-reads the document after the row was written by something other than this view model, like a
    /// recipe's "Add to Shopping List" sheet.  See the matching note in `ShoppingListDetailViewModel` on why pending
    /// save is dropped rather than flushed.
    func reloadAfterExternalChange() async {
        guard isLoaded else { return }
        saveTask?.cancel()
        saveTask = nil
        do {
            let list = try await database.read { [listId] db in
                try ShoppingList.where { $0.id.eq(listId) }.fetchOne(db)
            }
            text = list?.contentsForFreeform ?? ""
        } catch {
            logger.error("Error reloading shopping list \(self.listId): \(error)")
        }
    }

    /// Debounced save: collapses a burst of keystrokes into one write. Guarded on `isLoaded` so the
    /// initial text assignment during `load()` doesn't schedule a redundant save.
    func scheduleSave() {
        guard isLoaded else { return }
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
        let content = text
        let id = listId
        let log = logger
        let token = editorToken
        Task {
            do {
                try await database.write { db in
                    if var list = try ShoppingList.where { $0.id.eq(id) }.fetchOne(db) {
                        // Only the freeform payload — never touch `isFreeform` (owned by creation).
                        list.contentsForFreeform = content
                        list.lastModifiedDate = Date()
                        try ShoppingList.update(list).execute(db)
                    }
                }
                // The same list may be open in another window, holding its own copy of this text.
                ShoppingListChangeNotifier.shared.noteEditorChange(listId: id, source: token)
            } catch {
                log.error("Error saving shopping list \(id): \(error)")
            }
        }
    }
}
