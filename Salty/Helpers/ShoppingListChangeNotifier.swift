//
//  ShoppingListChangeNotifier.swift
//  Salty
//
//  Tells an open checklist that its row was changed from somewhere else in the app.
//
//  `ShoppingListDetailViewModel` loads its items once and saves the whole array back on a debounce,
//  which is right for inline editing but means it can't see a write it didn't make. On macOS a
//  recipe can be open in its own window while the main window shows that same list, so the "Add to
//  Shopping List" sheet can write underneath a live checklist. Without this the additions would be
//  invisible there, and the next keystroke in the checklist would save them away again.
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

    /// The list written to most recently by something other than its own checklist view model.
    private(set) var lastChangedListId: String?
    /// Bumped on every change, so two writes to the same list still read as two events.
    private(set) var changeCount = 0

    private init() {}

    func noteExternalChange(listId: String) {
        lastChangedListId = listId
        changeCount += 1
    }

    /// Whether the most recent change was to this list -- checked by a checklist when `changeCount`
    /// moves.
    func isMostRecentChange(forListId listId: String) -> Bool {
        lastChangedListId == listId
    }
}
