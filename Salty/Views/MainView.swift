//
//  MainView.swift
//  Salty
//
//  Created by Robert on 6/6/25.
//

import SwiftUI

struct MainView: View {
    // Own the root view model here (created once) rather than re-instantiating it inside `body`
    // on every render. `isNewLaunch` is set via the initializer so it's applied to the persisted
    // instance, not a throwaway one.
    @State private var viewModel = RecipeNavigationSplitViewModel(isNewLaunch: true)

    // Confirmation for a .saltyRecipe opened/AirDropped into Salty (the manual "Import from File…"
    // menu uses its own picker + sheet).
    @State private var importConfirmURL: URL?
    @State private var importConfirmNames: [String] = []
    @State private var showingImportConfirm = false

    var body: some View {
        RecipeNavigationSplitView(viewModel: viewModel)
            .onOpenURL { handleIncomingURL($0) }
            .alert("Import Recipe", isPresented: $showingImportConfirm) {
                Button("Cancel", role: .cancel) { importConfirmURL = nil }
                Button("Add") {
                    if let url = importConfirmURL {
                        Task { await viewModel.importOpenedRecipeFile(url) }
                    }
                    importConfirmURL = nil
                }
            } message: {
                Text(importConfirmMessage)
            }
    }

    private var importConfirmMessage: String {
        switch importConfirmNames.count {
        case 0: return "Add this recipe to your library?"
        case 1: return "Add “\(importConfirmNames[0])” to your library?"
        default: return "Add these \(importConfirmNames.count) recipes to your library?"
        }
    }

    private func handleIncomingURL(_ url: URL) {
        guard url.pathExtension.lowercased() == "saltyrecipe" else { return }
        importConfirmURL = url
        importConfirmNames = SaltyRecipeImportHelper.peekRecipeNames(url)
        showingImportConfirm = true
    }
}

#Preview {
    MainView()
}
