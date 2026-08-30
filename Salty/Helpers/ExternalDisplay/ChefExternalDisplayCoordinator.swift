//
//  ChefExternalDisplayCoordinator.swift
//  Salty
//
//  The link between Chef View on the phone and the external (AirPlay / HDMI) display scene.
//
//  When the user starts Screen Mirroring, the system offers the app the TV as a separate,
//  non-interactive scene (see ExternalDisplaySceneDelegate) instead of a raw mirror of the phone.
//  That scene needs to know one thing — which recipe (and scale) Chef View is showing right now —
//  and this coordinator is where that fact lives. The phone's ChefView publishes on appear and
//  clears on disappear; the TV root view observes `activeLaunch` and follows.
//
//  A singleton rather than app-owned `@State`, because its whole reason to exist is bridging two
//  worlds that don't share a SwiftUI environment: the app's scenes and a UIKit-created external
//  scene. iOS-only — on macOS the Chef View window is dragged to the TV instead (AirPlay Display),
//  and no coordination is needed.
//

#if !os(macOS)

import Foundation

@Observable
@MainActor
final class ChefExternalDisplayCoordinator {
    static let shared = ChefExternalDisplayCoordinator()

    private init() {}

    /// What the TV should show, or nil for the placeholder. Carries the scale so a recipe scaled on
    /// the phone shows the same quantities on the TV.
    private(set) var activeLaunch: ChefViewLaunch?

    /// True while an external display scene is connected. Lets the phone UI hint that Chef View is
    /// showing on the TV (nothing reads it yet; the scene delegate keeps it accurate regardless).
    private(set) var isExternalDisplayConnected = false

    /// Where in the ingredient list the phone is looking. The TV's copy can't be scrolled by hand,
    /// so it follows this instead — see ChefIngredientsScrollSync.
    private(set) var ingredientAnchor: ChefIngredientsAnchor = .top

    // MARK: - Published by the phone's Chef View

    func chefViewAppeared(_ launch: ChefViewLaunch) {
        // A different recipe (or the same one rescaled) is a different list: whatever the phone
        // last reported describes rows that are about to be replaced.
        if activeLaunch != launch {
            ingredientAnchor = .top
        }
        activeLaunch = launch
    }

    /// Clears the TV only if the disappearing Chef View is the one it's showing. During a quick
    /// close-and-reopen the new cover's `onAppear` can land before the old one's `onDisappear`, and
    /// an unconditional clear would blank the TV that just started showing the new recipe.
    func chefViewDisappeared(recipeId: String) {
        if activeLaunch?.recipeId == recipeId {
            activeLaunch = nil
            ingredientAnchor = .top
        }
    }

    /// Reported by the phone's ingredient list as it scrolls.
    func setIngredientAnchor(_ anchor: ChefIngredientsAnchor) {
        guard ingredientAnchor != anchor else { return }
        ingredientAnchor = anchor
    }

    // MARK: - Published by the external scene delegate

    func externalSceneDidConnect() {
        isExternalDisplayConnected = true
    }

    func externalSceneDidDisconnect() {
        isExternalDisplayConnected = false
    }
}

#endif
