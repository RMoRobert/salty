//
//  ShoppingListFreeformView.swift
//  Salty
//
//  Created by Robert on 7/24/26.
//

import SwiftUI

/// Freeform (Markdown-style) editor for one shopping list — a plain text blob the user structures
/// however they like (headings, sections per store, notes). The counterpart to the structured
/// `ShoppingListDetailView`; which one shows is decided by the list's `isFreeform` flag. The parent
/// recreates this view per list via `.id(...)`.
struct ShoppingListFreeformView: View {
    @State private var viewModel: ShoppingListFreeformViewModel
    @AppStorage("monospacedBulkEditFont") private var monospacedFont = false
    /// Sticky across lists and launches — a user who prefers reading their list formatted shouldn't
    /// have to flip this every time.
    @AppStorage("shoppingListFreeformShowsPreview") private var showsPreview = false

    init(listId: String) {
        _viewModel = State(initialValue: ShoppingListFreeformViewModel(listId: listId))
    }

    var body: some View {
        Group {
            if showsPreview {
                // Wait for the load before building the web view. Rendering it immediately would
                // create a WKWebView loading an EMPTY document, then throw it away a moment later
                // when `load()` lands and the content id changes — and a web view that's asked to
                // load and is then discarded mid-layout intermittently paints nothing, which is why
                // the preview sometimes stayed blank until the Edit/Preview picker was toggled.
                if viewModel.isLoaded {
                    MarkdownPreviewView(text: viewModel.text)
                } else {
                    ProgressView()
                }
            } else {
                TextEditor(text: $viewModel.text)
                    .font(monospacedFont ? .body.monospaced() : .body)
                    .overlay(alignment: .topLeading) {
                        if viewModel.isLoaded && viewModel.text.isEmpty {
                            Text("Type your list here. Use Markdown format, e.g., “# Heading” for sections and “* item” for entries.")
                                .foregroundStyle(.tertiary)
                                //.padding(.top, 8)
                                .padding(.leading, 2)
                                .allowsHitTesting(false)
                        }
                    }
                    .padding()
            }
        }
        // NOT `.task { }`: SwiftUI cancels that when the view's identity churns, and during a push it
        // can cancel a load for a view that then stays on screen — leaving `isLoaded` false forever,
        // since nothing re-runs it. That was the "preview is blank until I toggle Edit/Preview" bug.
        // An unstructured Task isn't tied to the view lifecycle. `load()` is idempotent and guards on
        // `isLoaded`, so re-appearing is cheap and finishing after a dismissal is harmless.
        .onAppear {
            Task { await viewModel.load() }
        }
        .onChange(of: viewModel.text) { _, _ in
            viewModel.scheduleSave()
        }
        .onDisappear {
            viewModel.flush()
        }
        // Ingredients added from a recipe elsewhere in the app land in the database, not in this
        // view model's in-memory text — pick them up rather than saving over them.
        .onChange(of: ShoppingListChangeNotifier.shared.changeCount) {
            guard ShoppingListChangeNotifier.shared.isMostRecentChange(forListId: viewModel.listId) else { return }
            Task { await viewModel.reloadAfterExternalChange() }
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Picker("View", selection: $showsPreview) {
                    Label("Edit", systemImage: "long.text.page.and.pencil").tag(false)
                    Label("Preview", systemImage: "eye").tag(true)
                }
                .pickerStyle(.segmented)
                .labelStyle(.iconOnly)
            }
        }
        .onChange(of: showsPreview) { _, isPreview in
            // Switching to preview leaves the editor: make sure the debounced text is committed so
            // what's rendered (and what a background sync would see) is the saved state.
            if isPreview {
                viewModel.flush()
            }
        }
    }
}

#Preview {
    NavigationStack {
        ShoppingListFreeformView(listId: "shopping-list-1-id")
    }
}
