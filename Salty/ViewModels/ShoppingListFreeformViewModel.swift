//
//  ShoppingListFreeformViewModel.swift
//  Salty
//
//  Created by Robert on 7/24/26.
//

import Foundation
import OSLog
import SQLiteData

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

    @ObservationIgnored
    private var saveTask: Task<Void, Never>?

    init(listId: String) {
        self.listId = listId
    }

    func load() async {
        guard !isLoaded else { return }
        do {
            let list = try await database.read { [listId] db in
                try ShoppingList.where { $0.id.eq(listId) }.fetchOne(db)
            }
            guard let list else { return }
            text = list.contentsForFreeform ?? ""
            isLoaded = true
        } catch {
            logger.error("Error loading shopping list \(self.listId): \(error)")
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
            } catch {
                log.error("Error saving shopping list \(id): \(error)")
            }
        }
    }
}
