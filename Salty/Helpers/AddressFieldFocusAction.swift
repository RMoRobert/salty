//
//  AddressFieldFocusAction.swift
//  Salty
//

import SwiftUI

/// Moves focus to the web importer's address field.
///
/// Published by the web import browser with `focusedSceneValue`, so File ▸ Open Location resolves to
/// the frontmost scene that actually has an address field. Every other window leaves it nil, which
/// disables the menu item — per HIG, disabled rather than hidden. Mirrors `SearchFieldFocusAction`,
/// and is scene-scoped for the same reason: a notification would fire in every open window at once.
///
/// A menu command rather than `onKeyPress`: the address field lives in the window toolbar, and key
/// presses there don't reliably reach the view that owns the focus state. It also makes ⌘L
/// discoverable, which a bare key handler never is.
struct AddressFieldFocusAction: Equatable {
    private let focus: @MainActor () -> Void

    init(_ focus: @escaping @MainActor () -> Void) {
        self.focus = focus
    }

    @MainActor
    func callAsFunction() {
        focus()
    }

    /// A scene has at most one address field, so any two actions from a scene are interchangeable.
    /// Comparing equal keeps a rebuilt closure from republishing the focused value on every update.
    static func == (lhs: Self, rhs: Self) -> Bool { true }
}

extension FocusedValues {
    @Entry var addressFieldFocusAction: AddressFieldFocusAction?
}
