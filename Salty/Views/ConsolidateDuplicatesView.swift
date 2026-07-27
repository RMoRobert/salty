//
//  ConsolidateDuplicatesView.swift
//  Salty
//
//  "Consolidate Duplicate Categories, Courses, and Tags" (File ▸ Library): lists library rows that
//  share a name and folds each set into a single row on request. Unlike the recipe-duplicates report,
//  this one does act — but only on the groups the user leaves checked, and only after confirming.
//

import SwiftUI

struct ConsolidateDuplicatesView: View {
    @State private var viewModel = ConsolidateDuplicatesViewModel()
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Group {
            if !viewModel.hasScanned {
                ProgressView("Looking for duplicates…")
            } else if viewModel.groups.isEmpty {
                ContentUnavailableView {
                    Label("No Duplicates Found", systemImage: "checkmark.circle")
                } description: {
                    Text("No two categories, courses, or tags share a name.")
                }
            } else {
                duplicatesList
            }
        }
        .navigationTitle("Consolidate Duplicates")
        #if !os(macOS)
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            #if !os(macOS)
            ToolbarItemGroup(placement: .bottomBar) {
                Button(viewModel.selectedGroupIDs.isEmpty ? "Select All" : "Deselect All") {
                    if viewModel.selectedGroupIDs.isEmpty {
                        viewModel.selectAll()
                    } else {
                        viewModel.deselectAll()
                    }
                }
                .disabled(viewModel.groups.isEmpty)
                Spacer()
                Button("Merge…") {
                    viewModel.showingMergeConfirmation = true
                }
                .disabled(!viewModel.canMerge)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") { dismiss() }
            }
            #else
            ToolbarItem(placement: .automatic) {
                Button(viewModel.selectedGroupIDs.isEmpty ? "Select All" : "Deselect All") {
                    if viewModel.selectedGroupIDs.isEmpty {
                        viewModel.selectAll()
                    } else {
                        viewModel.deselectAll()
                    }
                }
                .disabled(viewModel.groups.isEmpty)
            }
            ToolbarItem(placement: .primaryAction) {
                Button("Merge…", systemImage: "arrow.triangle.merge") {
                    viewModel.showingMergeConfirmation = true
                }
                .disabled(!viewModel.canMerge)
            }
            #endif
        }
        .alert("Merge Duplicates?", isPresented: $viewModel.showingMergeConfirmation) {
            Button("Cancel", role: .cancel) { }
            Button("Merge") {
                Task { await viewModel.mergeSelected() }
            }
        } message: {
            Text("\(viewModel.selectedRemovalCount) item\(viewModel.selectedRemovalCount == 1 ? "" : "s") will be removed, and the recipes using them moved to the item that remains. This can’t be undone.")
        }
        .alert("Merge Complete", isPresented: mergeSummaryPresented) {
            Button("OK") { viewModel.lastMergeSummary = nil }
        } message: {
            if let summary = viewModel.lastMergeSummary {
                Text("Removed \(summary.removedItems) duplicate item\(summary.removedItems == 1 ? "" : "s") across \(summary.mergedGroups) name\(summary.mergedGroups == 1 ? "" : "s"), updating \(summary.touchedRecipes) recipe\(summary.touchedRecipes == 1 ? "" : "s").")
            }
        }
        .errorAlert($viewModel.operationError)
        .task {
            if !viewModel.hasScanned {
                await viewModel.scan()
            }
        }
    }

    /// Drives the post-merge summary alert; dismissing clears the stored summary.
    private var mergeSummaryPresented: Binding<Bool> {
        Binding(
            get: { viewModel.lastMergeSummary != nil },
            set: { if !$0 { viewModel.lastMergeSummary = nil } }
        )
    }

    private var duplicatesList: some View {
        List {
            ForEach(viewModel.groupsByKind, id: \.kind) { section in
                Section {
                    ForEach(section.groups) { group in
                        Toggle(isOn: Binding(
                            get: { viewModel.isSelected(group) },
                            set: { viewModel.setSelected(group, $0) }
                        )) {
                            DuplicateGroupSummaryView(group: group)
                        }
                    }
                } header: {
                    Text(section.kind.pluralLabel)
                }
            }
        }
        #if os(macOS)
        .alternatingRowBackgrounds()
        #endif
        .safeAreaInset(edge: .top) {
            Text("Each set below is merged into the item used by the most recipes. Recipes keep every category, course, and tag they already have.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .scenePadding(.horizontal)
                .padding(.vertical, 6)
                .background(.bar)
        }
    }
}

// MARK: - Row

/// One duplicate-name set: what survives, and what gets folded into it.
private struct DuplicateGroupSummaryView: View {
    let group: LibraryDuplicateGroup

    /// "“breads” (2 recipes), “Breads ” (no recipes)" — the rows this merge removes.
    private var duplicatesDescription: String {
        group.duplicates
            .map { item in
                let count = item.recipeCount
                let recipes = count == 0 ? "no recipes" : "\(count) recipe\(count == 1 ? "" : "s")"
                return "“\(item.name)” (\(recipes))"
            }
            .formatted(.list(type: .and))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack {
                Label(group.name, systemImage: group.kind.systemImage)
                Spacer()
                Text(group.survivor.recipeCount == 1 ? "1 recipe" : "\(group.survivor.recipeCount) recipes")
                    .foregroundStyle(.secondary)
            }
            Text("Absorbs \(duplicatesDescription)")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    NavigationStack {
        ConsolidateDuplicatesView()
    }
}
