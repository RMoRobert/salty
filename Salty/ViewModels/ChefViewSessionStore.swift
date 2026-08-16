//
//  ChefViewSessionStore.swift
//  Salty
//
//  App-level home for Chef View cooking progress, keyed by recipe id.
//
//  A single shared instance, held by SaltyApp as `@State` and injected with `.environment`, so
//  leaving Chef View to glance at another recipe (or, on macOS, opening the same recipe in a second
//  Chef View window) comes back to the same checked ingredients and current step. Progress lives
//  for the app session and no longer: see the note in ChefSessionState.
//
//  `shared` exists because the iOS external-display scene (ExternalDisplaySceneDelegate) is created
//  by UIKit outside the SwiftUI environment, and its Chef View must see the SAME progress the
//  phone's does — that sharing is the whole mechanism by which the TV follows along.
//

import Foundation

@Observable
@MainActor
final class ChefViewSessionStore {
    static let shared = ChefViewSessionStore()

    private var sessions: [String: ChefSessionState] = [:]

    /// Current progress for a recipe — an empty session for one that hasn't been cooked yet.
    func state(for recipeId: String) -> ChefSessionState {
        sessions[recipeId] ?? ChefSessionState()
    }

    /// Mutates a recipe's progress in place. Entries are dropped once they're back to pristine so
    /// the store doesn't accumulate empty sessions for every recipe that was merely opened.
    func update(recipeId: String, _ mutate: (inout ChefSessionState) -> Void) {
        var state = state(for: recipeId)
        mutate(&state)
        if state.isPristine {
            sessions.removeValue(forKey: recipeId)
        } else {
            sessions[recipeId] = state
        }
    }

    func reset(recipeId: String) {
        sessions.removeValue(forKey: recipeId)
    }

    /// True when there's cooking progress worth returning to (drives "Start Over" affordances).
    func hasProgress(for recipeId: String) -> Bool {
        !state(for: recipeId).isPristine
    }
}
