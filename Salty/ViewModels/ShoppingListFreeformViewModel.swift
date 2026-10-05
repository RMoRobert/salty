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

/// Backs the freeform (Markdown-style) editor for one shopping list. Mirrors the debounced-save,
/// observed-row pattern of `ShoppingListDetailViewModel` (see the notes there), but the payload is a
/// single text blob (`contentsForFreeform`). The view is recreated per list via `.id(...)`, so
/// `load()` runs once.
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

    /// The row as the database holds it, kept live. The view watches it and hands every change to
    /// `storedRowDidChange(to:)`; after `load()` nothing here reads it directly.
    @ObservationIgnored
    @FetchOne var storedRow: ShoppingList?

    /// The stamp of the row as this editor last loaded, observed or wrote it: what the next save
    /// expects to find, and how a change notification is told from a repeat.
    @ObservationIgnored
    private var storedStamp: ShoppingListStamp?

    @ObservationIgnored
    private var saveTask: Task<Void, Never>?
    /// The database write in flight (or the last one started). Writes queue behind one another.
    @ObservationIgnored
    private var writeTask: Task<Void, Never>?

    /// The text as last read from or written to the database. Saves are triggered by the view's
    /// `onChange(of: text)`, which can't tell typing from `storedRowDidChange(to:)` assigning
    /// `text` -- so without this, every reload was saved straight back as a *new* edit. With the
    /// list open in two windows, that echo reached the window being typed in about 0.4s after its
    /// own save and reloaded it with its own now-stale text, dropping the keystrokes typed since
    /// and (because the editor's string was replaced wholesale) throwing the cursor to the end.
    @ObservationIgnored
    private var storedText = ""

    /// The text the most recent write carried, so its own change notification is recognised
    /// rather than mistaken for an outside edit.
    @ObservationIgnored
    private var writtenText: String?

    /// How long a burst of keystrokes settles before it is written. Injectable for tests.
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
                try await $storedRow.load()
                // Re-check after the suspension: onAppear can fire twice in quick succession, and two
                // in-flight loads both pass the guard at the top. Without this, whichever lands SECOND
                // would overwrite `text` — including any keystrokes typed since the first landed.
                guard !isLoaded else { return }
                // A missing row is a legitimately empty document, not a reason to keep waiting.
                let row = storedRow
                text = row?.contentsForFreeform ?? ""
                storedText = text
                storedStamp = ShoppingListStamp(lastModifiedDate: row?.lastModifiedDate)
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

    /// Takes in a change to the stored row. The view calls this whenever `storedRow` changes. See
    /// `ShoppingListDetailViewModel.storedRowDidChange(to:)` for the rules; the one difference is
    /// that an identical text is left alone, since replacing an editor's string resets its selection.
    func storedRowDidChange(to row: ShoppingList?) {
        guard isLoaded else { return }
        let stamp = ShoppingListStamp(lastModifiedDate: row?.lastModifiedDate)
        guard stamp != storedStamp else { return }
        storedStamp = stamp
        let stored = row?.contentsForFreeform ?? ""
        if stored == text || stored == writtenText {
            storedText = stored
            return
        }
        saveTask?.cancel()
        saveTask = nil
        writeTask?.cancel()
        writeTask = nil
        writtenText = nil
        storedText = stored
        if text != stored {
            text = stored
        }
    }

    /// Debounced save: collapses a burst of keystrokes into one write. Guarded on `isLoaded` so the
    /// initial text assignment during `load()` doesn't schedule a redundant save, and on `storedText`
    /// so a reload (or typing that ends up back where the database already is) doesn't either.
    func scheduleSave() {
        guard isLoaded else { return }
        saveTask?.cancel()
        guard text != storedText else {
            saveTask = nil
            return
        }
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
        let content = text
        let id = listId
        let log = logger
        // Queued behind the previous write, not cancelling it -- see ShoppingListDetailViewModel.
        let previous = writeTask
        writeTask = Task {
            await previous?.value
            guard !Task.isCancelled else { return }
            writtenText = content
            let expected = storedStamp
            do {
                let written = try await database.write { db in
                    // Only the freeform payload — never touch `isFreeform` (owned by creation).
                    try ShoppingListWriter.update(id: id, in: db, expecting: expected) { list in
                        list.contentsForFreeform = content
                    }
                }
                // Recorded only once the row holds it. Set before the write, a failed save left
                // `text == storedText`, so `scheduleSave` took the edit as already saved and never
                // retried; the keystrokes were silently lost until the next differing edit.
                storedText = content
                if let written {
                    storedStamp = ShoppingListStamp(of: written)
                }
            } catch is CancellationError {
                // Superseded by an outside change, which has already taken what is stored.
            } catch ShoppingListWriterError.modifiedElsewhere {
                // The row moved on under this editor; this text was built on the old one. The
                // observation delivers the newer row and replaces the text.
                log.info("Dropped a stale save of shopping list \(id): it was changed elsewhere")
            } catch {
                log.error("Error saving shopping list \(id): \(error)")
            }
        }
    }
}
