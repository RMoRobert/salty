//
//  ShoppingListDetailView.swift
//  Salty
//
//  Created by Robert on 7/24/26.
//

import SwiftUI

/// Reminders-style checklist for one shopping list: tap-to-check items, inline text editing, and
/// heading rows for grouping by store/category/aisle. The parent recreates this view per list via
/// `.id(listId)`.
struct ShoppingListDetailView: View {
    @State private var viewModel: ShoppingListDetailViewModel
    @AppStorage("shoppingListHideCompleted") private var hideCompleted = false
    @FocusState private var focusedItemId: String?
    @State private var showingConvertConfirmation = false

    init(listId: String) {
        _viewModel = State(initialValue: ShoppingListDetailViewModel(listId: listId))
    }

    private var visibleItems: [ShoppingListListContents] {
        hideCompleted ? viewModel.items.filter { !($0.isCompleted ?? false) } : viewModel.items
    }

    // Reordering with hidden rows is ambiguous (where do the hidden neighbors go?), so moves are
    // only allowed while every item is visible.
    private var isMoveDisabled: Bool {
        hideCompleted && viewModel.hasCompletedItems
    }

    var body: some View {
        Group {
            if viewModel.isLoaded && viewModel.items.isEmpty {
                ContentUnavailableView {
                    Text("No Items")
                } description: {
                    Text("Items added to this list will display here.")
                } actions: {
                    Button("New Item", systemImage: "plus") {
                        addAndFocusItem()
                    }
                }
            } else {
                List {
                    ForEach(visibleItems) { item in
                        ShoppingListItemRowView(
                            item: item,
                            viewModel: viewModel,
                            focus: $focusedItemId,
                            onSubmit: { handleSubmit(from: item) }
                        )
                        .moveDisabled(isMoveDisabled)
                        // Rules between every row make a shopping list read as a dense table; without
                        // them the checkmarks carry the structure. `.listStyle(.plain)` alone doesn't
                        // drop them — the separators are per-row, so they're hidden per-row.
                        .listRowSeparator(.hidden)
                    }
                    .onDelete { offsets in
                        let ids = offsets.map { visibleItems[$0].id }
                        for id in ids {
                            viewModel.deleteItem(id: id)
                        }
                    }
                    .onMove { source, destination in
                        // Only reachable when nothing is hidden (see isMoveDisabled), so visible
                        // offsets are full-array offsets.
                        viewModel.moveItems(fromOffsets: source, toOffset: destination)
                    }
                }
                .listStyle(.plain)
                
            }
        }
        .task {
            await viewModel.load()
        }
        .onDisappear {
            viewModel.removeEmptyItems()
            viewModel.flush()
        }
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                Button("New Item", systemImage: "plus") {
                    addAndFocusItem()
                }
                Menu {
                    Button("New Heading", systemImage: "textformat") {
                        addAndFocusItem(isHeading: true)
                    }
                    Divider()
                    Toggle("Hide Completed", isOn: $hideCompleted)
                    Button("Uncheck All Items", systemImage: "circle") {
                        viewModel.uncheckAll()
                    }
                    .disabled(!viewModel.hasCompletedItems)
                    Button("Clear Completed", systemImage: "checkmark.circle.badge.xmark", role: .destructive) {
                        withAnimation {
                            viewModel.clearCompleted()
                        }
                    }
                    .disabled(!viewModel.hasCompletedItems)
                    Divider()
                    Button("Convert to Freeform Text", systemImage: "text.alignleft") {
                        showingConvertConfirmation = true
                    }
                    #if !os(macOS)
                    Divider()
                    EditButton()
                    #endif
                } label: {
                    Label("More", systemImage: isLiquidGlassAvailable() ? "ellipsis" : "ellipsis.circle")
                }
            }
        }
        .confirmationDialog(
            "Convert to Freeform Text?",
            isPresented: $showingConvertConfirmation,
            titleVisibility: .visible
        ) {
            Button("Convert") {
                viewModel.convertToFreeform()
            }
            Button("Cancel", role: .cancel) { }
        } message: {
            Text("This turns the checklist into an editable text document. Item stars will be lost, and you can't switch it back to a checklist.")
        }
    }

    private func addAndFocusItem(isHeading: Bool = false) {
        let newId = viewModel.addItem(isHeading: isHeading)
        focusedItemId = newId
    }

    /// Return key: keep the entry flow going by inserting a fresh item right below the row being
    /// edited (an empty submitted row just ends editing instead).
    private func handleSubmit(from item: ShoppingListListContents) {
        guard let current = viewModel.items.first(where: { $0.id == item.id }),
              !current.text.trimmingCharacters(in: .whitespaces).isEmpty else {
            viewModel.removeEmptyItems()
            focusedItemId = nil
            return
        }
        let newId = viewModel.addItem(after: item.id)
        focusedItemId = newId
    }
}

// MARK: - Row

private struct ShoppingListItemRowView: View {
    let item: ShoppingListListContents
    let viewModel: ShoppingListDetailViewModel
    var focus: FocusState<String?>.Binding
    let onSubmit: () -> Void

    private var isHeading: Bool { item.isHeading ?? false }
    private var isCompleted: Bool { item.isCompleted ?? false }
    private var isImportant: Bool { item.isImportant ?? false }

    private var textBinding: Binding<String> {
        Binding(
            get: { viewModel.items.first(where: { $0.id == item.id })?.text ?? "" },
            set: { viewModel.updateText(id: item.id, text: $0) }
        )
    }

    var body: some View {
        HStack {
            if isHeading {
                TextField("Heading", text: textBinding)
                    .font(.headline)
            } else {
                Button(isCompleted ? "Completed" : "Not Completed",
                       systemImage: isCompleted ? "checkmark.circle.fill" : "circle") {
                    withAnimation {
                        viewModel.toggleCompleted(id: item.id)
                    }
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(isCompleted ? Color.accentColor : Color.secondary)
                .imageScale(.large)

                TextField("Item", text: textBinding)
                    .foregroundStyle(isCompleted ? .secondary : .primary)

                if isImportant {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.orange)
                        .imageScale(.small)
                        .accessibilityLabel("Important")
                }
            }
        }
        .focused(focus, equals: item.id)
        .onSubmit(onSubmit)
        #if !os(macOS)
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            if !isHeading {
                Button(isImportant ? "Remove Star" : "Star",
                       systemImage: isImportant ? "star.slash" : "star") {
                    viewModel.toggleImportant(id: item.id)
                }
                .tint(.orange)
            }
        }
        #endif
        .contextMenu {
            if !isHeading {
                Button(isImportant ? "Remove Star" : "Star",
                       systemImage: isImportant ? "star.slash" : "star.fill") {
                    viewModel.toggleImportant(id: item.id)
                }
            }
            Button("Delete", systemImage: "trash", role: .destructive) {
                withAnimation {
                    viewModel.deleteItem(id: item.id)
                }
            }
        }
    }
}

#Preview {
    NavigationStack {
        ShoppingListDetailView(listId: "shopping-list-2-id")
    }
}
