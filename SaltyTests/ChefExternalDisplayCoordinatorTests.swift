//
//  ChefExternalDisplayCoordinatorTests.swift
//  SaltyTests
//
//  The coordinator is a singleton (it bridges the SwiftUI world and the UIKit-created external
//  scene, which share nothing else), so these tests exercise the shared instance and restore it to
//  idle when they finish. `.serialized` keeps them from interleaving on that shared state.
//
//  iOS-only, like the type: on macOS the Chef View window is dragged to the TV instead.
//

#if !os(macOS)

import Testing
import Foundation
@testable import Salty

@Suite(.serialized)
@MainActor
struct ChefExternalDisplayCoordinatorTests {

    private var coordinator: ChefExternalDisplayCoordinator { .shared }

    /// Every test starts and ends idle, so leftover state can't leak between them.
    private func resetToIdle() {
        if let active = coordinator.activeLaunch {
            coordinator.chefViewDisappeared(recipeId: active.recipeId)
        }
        if coordinator.isExternalDisplayConnected {
            coordinator.externalSceneDidDisconnect()
        }
        coordinator.setIngredientAnchor(.top)
    }

    @Test func appearingChefViewDrivesTheDisplay() {
        resetToIdle()
        defer { resetToIdle() }

        let launch = ChefViewLaunch(recipeId: "recipe-a", scalePercent: 2.0)
        coordinator.chefViewAppeared(launch)

        #expect(coordinator.activeLaunch == launch, "the TV should follow the recipe AND its scale")
    }

    @Test func disappearingClearsOnlyItsOwnRecipe() {
        resetToIdle()
        defer { resetToIdle() }

        coordinator.chefViewAppeared(ChefViewLaunch(recipeId: "recipe-a"))
        coordinator.chefViewDisappeared(recipeId: "recipe-a")

        #expect(coordinator.activeLaunch == nil, "closing the active Chef View should idle the TV")
    }

    /// During a quick close-and-reopen, the new cover's `onAppear` can land before the old one's
    /// `onDisappear`. The stale disappear must not blank a TV that has already moved on.
    @Test func staleDisappearDoesNotBlankTheNewRecipe() {
        resetToIdle()
        defer { resetToIdle() }

        coordinator.chefViewAppeared(ChefViewLaunch(recipeId: "recipe-a"))
        coordinator.chefViewAppeared(ChefViewLaunch(recipeId: "recipe-b"))
        coordinator.chefViewDisappeared(recipeId: "recipe-a")

        #expect(coordinator.activeLaunch?.recipeId == "recipe-b")
    }

    /// Reopening the same recipe at a different scale must update the launch (the TV rebuilds its
    /// view model from it), not be mistaken for the same session.
    @Test func rescaledRelaunchReplacesTheOldScale() {
        resetToIdle()
        defer { resetToIdle() }

        coordinator.chefViewAppeared(ChefViewLaunch(recipeId: "recipe-a", scalePercent: 1.0))
        coordinator.chefViewAppeared(ChefViewLaunch(recipeId: "recipe-a", scalePercent: 0.5))

        #expect(coordinator.activeLaunch?.scalePercent == 0.5)
    }

    // MARK: - Ingredient scroll mirroring

    @Test func ingredientAnchorFollowsThePhone() {
        resetToIdle()
        defer { resetToIdle() }

        coordinator.chefViewAppeared(ChefViewLaunch(recipeId: "recipe-a"))
        coordinator.setIngredientAnchor(.item(index: 4))

        #expect(coordinator.ingredientAnchor == .item(index: 4))

        coordinator.setIngredientAnchor(.top)

        #expect(coordinator.ingredientAnchor == .top, "back at the top of the phone's list")
    }

    /// The end of the list is reported as the end, not as whichever row happens to be at the top of
    /// the phone there — the display may hold fewer rows, and scrolling that row to its top would
    /// leave the last ingredients unreachable on both devices.
    @Test func reachingTheEndOfThePhoneListAnchorsToTheEnd() {
        resetToIdle()
        defer { resetToIdle() }

        coordinator.chefViewAppeared(ChefViewLaunch(recipeId: "recipe-a"))
        coordinator.setIngredientAnchor(.item(index: 12))
        coordinator.setIngredientAnchor(.bottom)

        #expect(coordinator.ingredientAnchor == .bottom)
    }

    /// The anchor is an index into one recipe's ingredients, so carrying it into another recipe
    /// would scroll the TV to an unrelated row.
    @Test func switchingRecipesForgetsTheIngredientAnchor() {
        resetToIdle()
        defer { resetToIdle() }

        coordinator.chefViewAppeared(ChefViewLaunch(recipeId: "recipe-a"))
        coordinator.setIngredientAnchor(.item(index: 9))
        coordinator.chefViewAppeared(ChefViewLaunch(recipeId: "recipe-b"))

        #expect(coordinator.ingredientAnchor == .top)
    }

    /// Reappearing on the same recipe (the cover being re-presented, say) is not a new list, and
    /// must not throw away where the phone had scrolled to.
    @Test func relaunchingTheSameRecipeKeepsTheIngredientAnchor() {
        resetToIdle()
        defer { resetToIdle() }

        let launch = ChefViewLaunch(recipeId: "recipe-a")
        coordinator.chefViewAppeared(launch)
        coordinator.setIngredientAnchor(.item(index: 3))
        coordinator.chefViewAppeared(launch)

        #expect(coordinator.ingredientAnchor == .item(index: 3))
    }

    @Test func closingChefViewClearsTheIngredientAnchor() {
        resetToIdle()
        defer { resetToIdle() }

        coordinator.chefViewAppeared(ChefViewLaunch(recipeId: "recipe-a"))
        coordinator.setIngredientAnchor(.item(index: 2))
        coordinator.chefViewDisappeared(recipeId: "recipe-a")

        #expect(coordinator.ingredientAnchor == .top)
    }

    @Test func sceneConnectionIsTracked() {
        resetToIdle()
        defer { resetToIdle() }

        #expect(coordinator.isExternalDisplayConnected == false)
        coordinator.externalSceneDidConnect()
        #expect(coordinator.isExternalDisplayConnected == true)
        coordinator.externalSceneDidDisconnect()
        #expect(coordinator.isExternalDisplayConnected == false)
    }
}

#endif
