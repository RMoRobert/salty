//
//  ChefViewOpenAction.swift
//  Salty
//
//  Opens Chef View for the recipe on screen.
//
//  Published by the recipe detail view with `focusedSceneValue`, so the menu command resolves to
//  the frontmost scene that actually shows a recipe. Windows without one (the library editors, the
//  web importer) leave it nil, which disables the menu item — per HIG, disabled rather than hidden.
//  This mirrors SearchFieldFocusAction, and is scene-scoped for the same reason: a notification
//  would fire in every open window at once.
//

import SwiftUI

struct ChefViewOpenAction: Equatable {
    private let open: @MainActor () -> Void

    init(_ open: @escaping @MainActor () -> Void) {
        self.open = open
    }

    @MainActor
    func callAsFunction() {
        open()
    }

    /// A scene shows at most one recipe, so any two actions from a scene are interchangeable.
    /// Comparing equal keeps a rebuilt closure from republishing the focused value on every update.
    static func == (lhs: Self, rhs: Self) -> Bool { true }
}

extension FocusedValues {
    @Entry var chefViewOpenAction: ChefViewOpenAction?
}
