//
//  ShoppingListsListView.swift
//  Salty
//
//  Created by Robert on 7/24/26.
//

import SwiftUI

/// The middle (content) column when "All Lists" is selected: the collection of shopping lists, whose
/// selection drives the detail column. Mirrors the recipe-list column so the two flows ()and their
/// toolbars) line up. Owns its own create/rename/delete UI items.
struct ShoppingListsListView: View {
    @Bindable var viewModel: RecipeNavigationSplitViewModel

    @State private var showingNameAlert = false
    @State private var nameListId: String?
    @State private var listName = ""
    /// True when the name prompt follows a create (title "Name List") rather than a rename.
    @State private var isNamingNewList = false
    @State private var showingDeleteAlert = false
    /// Lists the pending delete applies to — one row for a context-menu delete, or the whole
    /// selection for a toolbar/keyboard delete.
    @State private var deleteCandidateIds = Set<String>()

    var body: some View {
        Group {
            if viewModel.shoppingLists.isEmpty {
                ContentUnavailableView {
                    Label("No Shopping Lists", systemImage: "cart")
                } description: {
                    Text("Create a checklist or a freeform list to get started.")
                } actions: {
                    VStack {
                        Button("New Checklist", systemImage: "plus") {
                            create(isFreeform: false)
                        }
                        .padding()
                        Button("New Freeform List", systemImage: "plus") {
                            create(isFreeform: true)
                        }
                    }
                    .scenePadding()
                }
            } else {
                List(selection: $viewModel.selectedShoppingListIDs) {
                    ForEach(viewModel.shoppingLists) { list in
                        ShoppingListRowView(list: list)
                            .tag(list.id)
                            #if !os(macOS)
                            .contextMenu {
                                listContextMenu(for: list)
                            }
                            #endif
                    }
                    #if !os(macOS)
                    .onDelete { offsets in
                        let ids = Set(offsets.map { viewModel.shoppingLists[$0].id })
                        Task { await viewModel.deleteShoppingLists(ids: ids) }
                    }
                    #endif
                }
                #if os(macOS)
                // Selection-aware menu: a right-click on one row acts on that row; on a multi-selection
                // it offers only the actions that make sense for several lists.
                .contextMenu(forSelectionType: String.self) { ids in
                    if ids.count == 1, let list = viewModel.shoppingLists.first(where: { $0.id == ids.first }) {
                        listContextMenu(for: list)
                    } else if ids.count > 1 {
                        Button("Delete…", systemImage: "trash", role: .destructive) {
                            confirmDelete(ids: ids)
                        }
                        .keyboardShortcut(.delete, modifiers: [.command])
                    }
                }
                .onDeleteCommand {
                    if !viewModel.selectedShoppingListIDs.isEmpty {
                        confirmDelete(ids: viewModel.selectedShoppingListIDs)
                    }
                }
                #endif
            }
        }
        .navigationTitle("Shopping Lists")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button(role: .destructive) {
                    confirmDelete(ids: viewModel.selectedShoppingListIDs)
                } label: {
                    Label("Delete List", systemImage: "trash")
                }
                .disabled(viewModel.selectedShoppingListIDs.isEmpty)

                Menu {
                    Button("New Checklist", systemImage: "checklist") {
                        create(isFreeform: false)
                    }
                    Button("New Freeform List", systemImage: "text.alignleft") {
                        create(isFreeform: true)
                    }
                } label: {
                    Label("New List", systemImage: "plus")
                } primaryAction: {
                    create(isFreeform: false)
                }
            }
        }
        .alert(isNamingNewList ? "Name List" : "Rename List", isPresented: $showingNameAlert) {
            TextField("Name", text: $listName)
            Button("Cancel", role: .cancel) { }
            Button(isNamingNewList ? "Save" : "Rename") {
                if let listId = nameListId {
                    let newName = listName
                    Task { await viewModel.renameShoppingList(id: listId, to: newName) }
                }
            }
        }
        .alert(deleteCandidateIds.count == 1 ? "Delete Shopping List?" : "Delete Shopping Lists?",
               isPresented: $showingDeleteAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Delete", role: .destructive) {
                let ids = deleteCandidateIds
                Task { await viewModel.deleteShoppingLists(ids: ids) }
            }
        } message: {
            // No name preview: a multi-selection has no single list to name.
            Text("Are you sure you want to delete \(deleteCandidateIds.count) shopping list\(deleteCandidateIds.count == 1 ? "" : "s")? This action cannot be undone.")
        }
    }

    @ViewBuilder
    private func listContextMenu(for list: ShoppingList) -> some View {
        Button("Rename…", systemImage: "pencil") {
            beginRename(list)
        }
        Button("Delete…", systemImage: "trash", role: .destructive) {
            confirmDelete(ids: [list.id])
        }
        #if os(macOS)
        .keyboardShortcut(.delete, modifiers: [.command])
        #endif
    }

    private func create(isFreeform: Bool) {
        Task {
            if let newList = await viewModel.createShoppingList(isFreeform: isFreeform) {
                nameListId = newList.id
                listName = newList.name
                isNamingNewList = true
                showingNameAlert = true
            }
        }
    }

    private func beginRename(_ list: ShoppingList) {
        nameListId = list.id
        listName = list.name
        isNamingNewList = false
        showingNameAlert = true
    }

    private func confirmDelete(ids: Set<String>) {
        guard !ids.isEmpty else { return }
        deleteCandidateIds = ids
        showingDeleteAlert = true
    }
}

// MARK: - Row

private struct ShoppingListRowView: View {
    let list: ShoppingList

    /// Different style names, same 22pt result on both platforms — macOS text styles run smaller, so
    /// `.title` there matches `.title2` on iOS. (`.title2` on macOS is only 17pt, which is why a single
    /// value looked right on iPhone and undersized on the Mac.) Still text styles, so Dynamic Type works.
    private var iconFont: Font {
        #if os(macOS)
        .title
        #else
        .title2
        #endif
    }

    /// A fixed gutter, so titles line up from row to row: `checklist` and `text.page` have different
    /// intrinsic widths, and without this each row's text starts at a slightly different x. Wider than
    /// the glyph, which is also what gives the icon its breathing room. `@ScaledMetric` keeps it in step
    /// with Dynamic Type so a larger glyph can't get clipped. Tune this for spacing in future if desired.
    @ScaledMetric(relativeTo: .title) private var iconWidth: CGFloat = 30

    var body: some View {
        // HStack rather than Label: Label aligns its icon to the title's baseline, which looks
        // top-heavy next to a two-line VStack.
        HStack {
            Image(systemName: list.isFreeform ? "text.page" : "checklist")
                .font(iconFont)
                .frame(width: iconWidth)
            VStack(alignment: .leading, spacing: 2) {
                Text(list.name)
                Text(list.contentsSummary)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }
}

#Preview {
    NavigationStack {
        ShoppingListsListView(
            viewModel: PreviewRecipeNavigationSplitViewModel(
                previewData: (recipes: [], categories: [], courses: [], tags: [])
            )
        )
    }
}
