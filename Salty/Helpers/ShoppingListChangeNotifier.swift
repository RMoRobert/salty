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

    private init() {}

    func noteExternalChange(listId: String) {
        changeCounts[listId, default: 0] += 1
    }

    /// The change count for one list — the value an open checklist observes. Coalesced deliveries
    /// are fine: any observed increase means "reload", however many writes it covers.
    func changeCount(for listId: String) -> Int {
        changeCounts[listId] ?? 0
    }
}
