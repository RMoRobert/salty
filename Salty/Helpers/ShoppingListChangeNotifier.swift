//
//  ShoppingListChangeNotifier.swift
//  Salty
//
//  Tells an open checklist that its row was changed from somewhere else in the app.
//
//  `ShoppingListDetailViewModel` loads its items once and saves the whole array back on a debounce,
//  which is right for inline editing but means it can't see a write it didn't make. On macOS a
//  recipe can be open in its own window while the main window shows that same list, so the "Add to
//  Shopping List" sheet can write underneath a live checklist. Sync does the same thing on every
//  platform: a list edited on another device (or in the server's web UI) is downloaded straight
//  into the database. Without this the additions would be invisible there, and the next keystroke
//  in the checklist would save them away again.
//
//  The editors themselves are the third source, and the sharpest one: "Open in New Window" can put
//  the same list in two editors at once, each holding its own copy. So a save announces itself too,
//  tagged with the editor that made it (`noteEditorChange`), and every *other* editor of that list
//  reloads.
//
//  Counters are kept PER LIST, not as one shared "most recent change": a single sync pass can
//  download several lists back-to-back, and SwiftUI coalesces `onChange` deliveries, so a view
//  watching a shared counter could observe only the final change and miss its own list's.
//
//  A main-actor observable rather than a `Notification`: both ends are already main-actor, and
//  `Notification` isn't `Sendable`, so the posting route would need concurrency escapes to say
//  something the observation system says plainly.
//

import Foundation

@Observable
@MainActor
final class ShoppingListChangeNotifier {
    static let shared = ShoppingListChangeNotifier()

    /// External-write count per list id. Monotonic within a run; never trimmed (a library holds a
    /// handful of lists, so the dictionary stays tiny).
    private(set) var changeCounts: [String: Int] = [:]

    /// Who made each list's most recent change: the editor's token, or nil when the write came from
    /// outside any open editor (the "Add to Shopping List" sheet, or sync).
    private(set) var changeSources: [String: UUID] = [:]

    private init() {}

    /// A write from outside the list editors — the "Add to Shopping List" sheet, or a sync download.
    func noteExternalChange(listId: String) {
        note(listId: listId, source: nil)
    }

    /// A write by one of the list editors, identified by its `editorToken`.
    ///
    /// The same list can be open in two windows at once ("Open in New Window"), and each editor holds
    /// the whole list in memory and saves it back wholesale — so without this the second window's
    /// next keystroke would write its stale copy over everything the first one just did. The editor
    /// that made the change ignores its own announcement (see `isOwnChange`): reloading a write you
    /// just made would only interrupt typing.
    func noteEditorChange(listId: String, source: UUID) {
        note(listId: listId, source: source)
    }

    private func note(listId: String, source: UUID?) {
        changeCounts[listId, default: 0] += 1
        changeSources[listId] = source
    }

    /// The change count for one list — the value an open checklist observes. Coalesced deliveries
    /// are fine: any observed increase means "reload", however many writes it covers.
    func changeCount(for listId: String) -> Int {
        changeCounts[listId] ?? 0
    }

    /// Whether the latest change to this list was made by `source` — that editor already has it.
    /// Coalescing is safe here too: if someone else wrote last, everyone else reloads, and the one
    /// stale editor that skipped an earlier round is reloading the newer state anyway.
    func isOwnChange(listId: String, source: UUID) -> Bool {
        changeSources[listId] == source
    }
}
