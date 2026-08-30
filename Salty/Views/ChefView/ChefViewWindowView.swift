//
//  ChefViewWindowView.swift
//  Salty
//
//  Root of the macOS "chef-view-window" scene. Chef View gets its own window on macOS (rather than
//  a sheet) so it can be sent full screen onto an external display or TV while the main app window
//  stays usable.
//

#if os(macOS)

import SwiftUI
import SaltyCore

struct ChefViewWindowView: View {
    @Binding var launch: ChefViewLaunch?
    @Environment(ChefViewSessionStore.self) private var sessionStore

    var body: some View {
        if let launch {
            ChefView(
                recipeId: launch.recipeId,
                scaleFactor: launch.scalePercent,
                sessionStore: sessionStore
            )
            // A restored window handed a different recipe rebuilds rather than reusing the old
            // view model, which is keyed to one recipe id.
            .id(launch.recipeId)
        } else {
            ContentUnavailableView("No Recipe Selected", systemImage: "list.bullet.rectangle")
        }
    }
}

#endif
