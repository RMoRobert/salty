//
//  SearchFieldFocusAction.swift
//  Salty
//

import SwiftUI

/// Moves focus to the recipe list's search field.
///
/// Published by the recipe list with `focusedSceneValue`, so Edit ▸ Find resolves to the
/// frontmost scene that actually has a search field. Windows without one (a single recipe,
/// the web importer) leave it nil, which disables the menu item — per HIG, disabled rather
/// than hidden — and lets ⌘F fall through to the standard Find bar for text editors there.
struct SearchFieldFocusAction: Equatable {
    private let focus: @MainActor () -> Void

    init(_ focus: @escaping @MainActor () -> Void) {
        self.focus = focus
    }

    @MainActor
    func callAsFunction() {
        focus()
    }

    /// A scene has at most one search field, so any two actions from a scene are interchangeable.
    /// Comparing equal keeps a rebuilt closure from republishing the focused value on every update.
    static func == (lhs: Self, rhs: Self) -> Bool { true }
}

extension FocusedValues {
    @Entry var searchFieldFocusAction: SearchFieldFocusAction?
}
