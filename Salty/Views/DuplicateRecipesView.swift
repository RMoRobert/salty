//
//  DuplicateRecipesView.swift
//  Salty
//
//  "Show Duplicate Recipes" (File ▸ Library): lists recipes whose content is identical, grouped, in
//  the spirit of iTunes' Show Duplicates. Reporting only — it never merges or removes anything on its
//  own; deleting a copy is an explicit, confirmed action.
//

import SwiftUI

struct DuplicateRecipesView: View {
    @State private var viewModel = DuplicateRecipesViewModel()
    /// Remembered between openings: a library that needs the loose setting once usually needs it again.
    @AppStorage("duplicateRecipeMatchLevel") private var matchLevel: RecipeDuplicateMatchLevel = .defaultLevel
    @Environment(\.dismiss) private var dismiss
    #if os(macOS)
    @Environment(\.openWindow) private var openWindow
    #endif

    var body: some View {
        Group {
            if !viewModel.hasScanned {
                ProgressView("Looking for duplicates…")
            } else if viewModel.groups.isEmpty {
                ContentUnavailableView {
                    Label("No Duplicate Recipes", systemImage: "checkmark.circle")
                } description: {
                    // Only point at the toolbar when there's actually something looser to switch to.
                    if matchLevel == .titleAndSource {
                        Text("No two recipes share a title and source.")
                    } else {
                        Text("No two recipes matched on \(matchLevel.displayName.lowercased()). Try a looser match from the toolbar.")
                    }
                }
            } else {
                duplicatesList
            }
        }
        .navigationTitle("Duplicate Recipes")
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            #if !os(macOS)
            ToolbarItemGroup(placement: .bottomBar) {
                Button(role: .destructive) {
                    viewModel.confirmDelete(ids: viewModel.selectedRecipeIDs)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .disabled(viewModel.selectedRecipeIDs.isEmpty)
                Spacer()
                matchLevelMenu
                Button("Rescan", systemImage: "arrow.clockwise") {
                    Task { await viewModel.scan() }
                }
                .disabled(viewModel.isScanning)
            }
            ToolbarItem(placement: .topBarLeading) {
                EditButton()
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
            #else
            ToolbarItem(placement: .automatic) {
                Button(role: .destructive) {
                    viewModel.confirmDelete(ids: viewModel.selectedRecipeIDs)
                } label: {
                    Label("Delete", systemImage: "trash")
                }
                .disabled(viewModel.selectedRecipeIDs.isEmpty)
            }
            ToolbarItem(placement: .automatic) {
                matchLevelMenu
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Rescan", systemImage: "arrow.clockwise") {
                    Task { await viewModel.scan() }
                }
                .disabled(viewModel.isScanning)
            }
            #endif
        }
        .alert(
            viewModel.deleteCandidateIDs.count == 1 ? "Delete Recipe?" : "Delete Recipes?",
            isPresented: $viewModel.showingDeleteConfirmation
        ) {
            Button("Cancel", role: .cancel) { viewModel.deleteCandidateIDs.removeAll() }
            Button("Delete", role: .destructive) {
                Task { await viewModel.deleteConfirmedRecipes() }
            }
        } message: {
            Text("Are you sure you want to delete \(viewModel.deleteCandidateIDs.count) recipe\(viewModel.deleteCandidateIDs.count == 1 ? "" : "s")? This action cannot be undone.")
        }
        .errorAlert($viewModel.operationError)
        .task(id: matchLevel) {
            // Scans on first appearance and again whenever the strictness changes — the results are
            // only meaningful for the level that produced them.
            await viewModel.scan(level: matchLevel)
        }
    }

    /// How alike two recipes have to be. Lives in the toolbar rather than a settings pane because
    /// finding the right level is part of using the command.
    private var matchLevelMenu: some View {
        Menu {
            Picker("Match Recipes On", selection: $matchLevel) {
                ForEach(RecipeDuplicateMatchLevel.allCases) { level in
                    Text(level.displayName).tag(level)
                }
            }
            .pickerStyle(.inline)
        } label: {
            Label("Match Recipes On", systemImage: "slider.horizontal.3")
        }
        .disabled(viewModel.isScanning)
    }

    private var duplicatesList: some View {
        List(selection: $viewModel.selectedRecipeIDs) {
            ForEach(viewModel.groups) { group in
                DuplicateGroupHeaderView(group: group)
                    .selectionDisabled()
                    .listRowSeparator(.hidden)
                ForEach(group.recipes) { recipe in
                    DuplicateRecipeRowView(recipe: recipe)
                        .tag(recipe.id)
                        #if !os(macOS)
                        .contextMenu {
                            recipeContextMenu(for: recipe)
                        }
                        .swipeActions {
                            Button(role: .destructive) {
                                viewModel.confirmDelete(ids: [recipe.id])
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                        }
                        #endif
                }
            }
        }
        #if os(macOS)
        // No `.alternatingRowBackgrounds()`: it stripes the empty space past the last row as though
        // there were more recipes, and the interleaved heading rows would throw off the alternation.
        .contextMenu(forSelectionType: String.self) { ids in
            if ids.count == 1, let recipe = recipe(for: ids.first) {
                recipeContextMenu(for: recipe)
            } else if ids.count > 1 {
                Button("Delete…", systemImage: "trash", role: .destructive) {
                    viewModel.confirmDelete(ids: ids)
                }
                .keyboardShortcut(.delete, modifiers: [.command])
            }
        }
        .onDeleteCommand {
            viewModel.confirmDelete(ids: viewModel.selectedRecipeIDs)
        }
        #endif
        .safeAreaInset(edge: .bottom) {
            HStack {
                Text(viewModel.summaryText)
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .scenePadding(.horizontal)
            .padding(.vertical, 4)
            .background(.bar)
        }
    }

    private func recipe(for id: String?) -> Recipe? {
        guard let id else { return nil }
        return viewModel.groups.lazy.flatMap(\.recipes).first { $0.id == id }
    }

    @ViewBuilder
    private func recipeContextMenu(for recipe: Recipe) -> some View {
        #if os(macOS)
        Button("Open in New Window", systemImage: "macwindow") {
            openWindow(id: "recipe-detail-window", value: recipe.id)
        }
        .keyboardShortcut(.return)
        Divider()
        #endif
        Button("Delete…", systemImage: "trash", role: .destructive) {
            viewModel.confirmDelete(ids: [recipe.id])
        }
    }
}

// MARK: - Group header

/// Styled to read as a section header even though it's an ordinary row (see the note in
/// `duplicatesList` for why it isn't a real one).
private struct DuplicateGroupHeaderView: View {
    let group: RecipeDuplicateGroup

    var body: some View {
        HStack {
            Text(group.name.isEmpty ? "(Untitled Recipe)" : group.name)
            Spacer()
            Text("\(group.recipes.count) copies")
        }
        .font(.subheadline)
        .foregroundStyle(.secondary)
        .padding(.top, 6)   // separates a group from the one above without a section's own spacing
    }
}

// MARK: - Row

/// Shows what can actually differ between copies — the dates, the image, and the marks the user has
/// put on one copy but not another (rating, favorite, want to make). Everything the match compares is
/// identical across the group by definition, so showing it again wouldn't help anyone choose.
private struct DuplicateRecipeRowView: View {
    let recipe: Recipe

    var body: some View {
        HStack {
            if let thumbnailData = recipe.imageThumbnailData {
                createXPImage(thumbnailData)
                    .resizable()
                    .aspectRatio(contentMode: .fit)
                    .frame(width: 40, height: 40)
                    .clipShape(.rect(cornerRadius: 5))
            } else {
                Image(systemName: "list.bullet.rectangle")
                    .font(.title3)
                    .foregroundStyle(.gray.opacity(0.4))
                    .frame(width: 40, height: 40)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(recipe.summary.isEmpty ? recipe.name : recipe.summary)
                    .lineLimit(1)
                Text("Created \(recipe.createdDate.formatted(date: .abbreviated, time: .shortened)) · Modified \(recipe.lastModifiedDate.formatted(date: .abbreviated, time: .shortened))")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            HStack {
                if recipe.imageFilename == nil && recipe.imageThumbnailData == nil {
                    Text("No image")
                }
                if recipe.wantToMake {
                    Image(systemName: "bookmark.fill")
                        .accessibilityLabel("Want to make")
                }
                if recipe.rating != .notSet {
                    Label(recipe.rating.stringValue(), systemImage: "star.fill")
                        .accessibilityLabel("Rated \(recipe.rating.stringValue())")
                }
                if recipe.isFavorite {
                    Image(systemName: "heart.fill")
                        .foregroundStyle(.red)
                        .accessibilityLabel("Favorite")
                }
            }
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    NavigationStack {
        DuplicateRecipesView()
    }
}
