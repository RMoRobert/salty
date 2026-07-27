//
//  RecipeDetailWindowView.swift
//  Salty
//
//  Dedicated recipe detail window for macOS (opened from the list).
//

#if os(macOS)

import SwiftUI

struct RecipeDetailWindowView: View {
    @Binding var recipeId: String?
    @AppStorage("webPreviews") private var useWebRecipeDetailView = false
    @State private var viewModel: RecipeDetailViewModel?
    @State private var showingEditSheet = false
    
    private var displayTitle: String {
        viewModel?.recipe?.name ?? "Recipe"
    }
    
    var body: some View {
        Group {
            if recipeId != nil {
                recipeContent()
                    .navigationTitle(displayTitle)
                    .toolbar {
                        ToolbarItem(placement: .primaryAction) {
                            Button {
                                showingEditSheet = true
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            .keyboardShortcut("e", modifiers: .command)
                            .disabled(viewModel?.recipe == nil)
                        }
                    }
            } else {
                ContentUnavailableView("No Recipe Selected", systemImage: "list.bullet.rectangle")
            }
        }
        .task(id: recipeId) {
            guard let id = recipeId else {
                viewModel = nil
                return
            }
            viewModel = RecipeDetailViewModel(recipeId: id)
        }
        .sheet(isPresented: $showingEditSheet) {
            if let recipe = viewModel?.recipe {
                NavigationStack {
                    RecipeDetailEditDesktopView(recipe: recipe, isNewRecipe: false, onNewRecipeSaved: nil)
                        .frame(minWidth: 625, minHeight: 650)
                }
            }
        }
    }
    
    @ViewBuilder
    private func recipeContent() -> some View {
        if let id = recipeId,
           let vm = viewModel,
           vm.recipeId == id,
           let recipe = vm.recipe {
            if useWebRecipeDetailView {
                RecipeDetailWebView(recipe: recipe)
                    .id(recipe.id)
            } else {
                RecipeDetailView(recipe: recipe, onScaledRecipeSaved: { newId in
                    recipeId = newId
                })
                .id(recipe.id)
            }
        } else {
            ProgressView("Loading recipe...")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

#endif
