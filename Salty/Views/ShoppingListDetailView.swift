//
//  ShoppingListDetailView.swift
//  Salty
//
//  Created by Robert on 7/24/26.
//

import SwiftUI
import SaltyCore

/// Reminders-style checklist for one shopping list: tap-to-check items, inline text editing, and
/// heading rows for grouping by store/category/aisle. The parent recreates this view per list via
/// `.id(listId)`.
struct ShoppingListDetailView: View {
    @State private var viewModel: ShoppingListDetailViewModel
    @AppStorage("shoppingListHideCompleted") private var hideCompleted = false
    @FocusState private var focusedItemId: String?
    @State private var showingConvertConfirmation = false
    /// macOS reorder arming: the row whose drag handle is under the pointer, if any. While set,
    /// every visible row is movable — arming per row instead capped drags at one position (see the
    /// move-disable note in ShoppingListItemRowView). Text stays instantly clickable because the
    /// pointer is on a handle, never on a field, while armed. Never set on iOS: rows only report
    /// handle hover on macOS.
    @State private var handleHoverRowId: String?

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

    /// Armed while the hovered handle still belongs to a visible row (guards against a stale id if
    /// that row gets deleted). Hover events freeze during a drag, so once armed this holds — and
    /// keeps every row movable — until the drop lands.
    private var isReorderArmed: Bool {
        guard let handleHoverRowId else { return false }
        return visibleItems.contains { $0.id == handleHoverRowId }
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
                            moveDisabledByFilter: isMoveDisabled,
                            isReorderArmed: isReorderArmed,
                            onHandleHover: { hovering in
                                if hovering {
                                    handleHoverRowId = item.id
                                } else if handleHoverRowId == item.id {
                                    handleHoverRowId = nil
                                }
                            },
                            onSubmit: { handleSubmit(from: item) }
                        )
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
                        withAnimation {
                            viewModel.moveItems(fromOffsets: source, toOffset: destination)
                        }
                        // Hover events were frozen during the drag, and the handle that armed it
                        // may have been recreated by the reorder, losing its hover-out event —
                        // disarm here and let a live hover re-arm.
                        handleHoverRowId = nil
                    }
                }
                .listStyle(.plain)
                
            }
        }
        // Unstructured Task rather than `.task { }` — see the matching note in ShoppingListFreeformView:
        // a `.task` cancelled during a push leaves the view stuck on neither its rows nor its empty state.
        .onAppear {
            Task { await viewModel.load() }
        }
        .onDisappear {
            viewModel.removeEmptyItems()
            viewModel.flush()
        }
        // Reminders behavior: a row the user never typed into vanishes the moment focus leaves it,
        // whether that's a tap into another row, Return, or dismissing the keyboard.
        .onChange(of: focusedItemId) { previousId, _ in
            guard let previousId else { return }
            withAnimation {
                viewModel.removeIfBlank(id: previousId)
            }
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
            Text("This turns the checklist into an editable text document. You can't switch it back to a checklist.")
        }
    }

    private func addAndFocusItem(isHeading: Bool = false) {
        // "New Item" while already editing a still-blank row of the same kind just stays in that
        // row (Reminders does the same) — repeated taps of + shouldn't stack up empty rows.
        if let focusedId = focusedItemId,
           let focused = viewModel.items.first(where: { $0.id == focusedId }),
           focused.isBlank, (focused.isHeading ?? false) == isHeading {
            return
        }
        // Any other blank row is an abandoned draft — clear it rather than accumulate.
        withAnimation {
            viewModel.removeEmptyItems()
        }
        let newId = viewModel.addItem(isHeading: isHeading)
        focusedItemId = newId
    }

    /// Return key: keep the entry flow going by inserting a fresh item right below the row being
    /// edited (an empty submitted row just ends editing instead, and removes itself).
    private func handleSubmit(from item: ShoppingListListContents) {
        guard let current = viewModel.items.first(where: { $0.id == item.id }), !current.isBlank else {
            withAnimation {
                viewModel.removeEmptyItems()
            }
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
    /// List-wide move disable from the parent (reordering while completed rows are hidden is
    /// ambiguous). Combined here with the macOS reorder arming below.
    let moveDisabledByFilter: Bool
    /// macOS: true while some row's drag handle is under the pointer (parent's `handleHoverRowId`).
    /// Unused on iOS.
    let isReorderArmed: Bool
    /// macOS: reports pointer enter/exit on this row's drag handle so the parent can arm reordering.
    /// Never called on iOS (the handle only exists on macOS).
    let onHandleHover: (Bool) -> Void
    let onSubmit: () -> Void

    #if os(macOS)
    @State private var isHoveringRow = false
    #endif

    private var isHeading: Bool { item.isHeading ?? false }
    private var isCompleted: Bool { item.isCompleted ?? false }

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
            }
            #if os(macOS)
            dragHandle
            #endif
        }
        .focused(focus, equals: item.id)
        .onSubmit(onSubmit)
        #if os(macOS)
        // `onMove` attaches a drag recognizer to the whole row, and that recognizer is what makes
        // clicking into the TextField need carefully-timed clicks (the click is held back in case
        // it becomes a drag). So rows stay move-disabled until the pointer reaches a drag handle —
        // clicks land in the text instantly, since a pointer on a handle is never on a text field.
        // Arming must be list-wide (any handle hovered → every row movable), not per-row: a drop
        // can't displace a move-disabled neighbor, and hover state freezes during a drag, so gating
        // each row on its own handle capped every drag at one position.
        .onHover { isHoveringRow = $0 }
        .moveDisabled(moveDisabledByFilter || !isReorderArmed)
        #else
        .moveDisabled(moveDisabledByFilter)
        #endif
        .contextMenu {
            Button("Delete", systemImage: "trash", role: .destructive) {
                withAnimation {
                    viewModel.deleteItem(id: item.id)
                }
            }
        }
    }

    #if os(macOS)
    /// Mouse-only reorder affordance, shown while the pointer is over the row (hidden when the
    /// hide-completed filter makes moves meaningless). Keyboard/VoiceOver users aren't losing
    /// anything that worked before: row dragging was always pointer-driven on macOS.
    private var dragHandle: some View {
        Image(systemName: "line.3.horizontal")
            .foregroundStyle(.tertiary)
            .opacity(isHoveringRow && !moveDisabledByFilter ? 1 : 0)
            .onHover { onHandleHover($0) }
            .accessibilityHidden(true)
    }
    #endif
}

#Preview {
    NavigationStack {
        ShoppingListDetailView(listId: "shopping-list-2-id")
    }
}
