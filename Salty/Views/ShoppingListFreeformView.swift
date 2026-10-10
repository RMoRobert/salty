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
    @Environment(\.scenePhase) private var scenePhase

    init(listId: String) {
        _viewModel = State(initialValue: ShoppingListFreeformViewModel(listId: listId))
    }

    var body: some View {
        Group {
            // The preview needs OS 26 (SwiftUI's WebView); before that the picker is hidden and a
            // preference saved on a newer system falls back to the editor.
            if showsPreview, #available(iOS 26.0, macOS 26.0, *) {
                // Wait for the load before building the web view, so it doesn't render an empty
                // document first. (With the earlier WebViewKit view, which was rebuilt whenever the
                // content changed, that discarded first view intermittently left the preview blank.)
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
        // iOS can kill a backgrounded app without warning, so a save still sitting in the debounce
        // is written the moment the scene stops being active rather than waiting for `onDisappear`.
        .onChange(of: scenePhase) { _, phase in
            if phase != .active {
                viewModel.flush()
            }
        }
        // Writes this view model didn't make (a recipe's "Add to Shopping List" sheet, a sync
        // download, or this same list being edited in another window) go to the database, not to the
        // in-memory text. The view model observes the row and sorts its own writes from theirs.
        .onChange(of: viewModel.storedRow) { _, row in
            viewModel.storedRowDidChange(to: row)
        }
        .toolbar {
            if #available(iOS 26.0, macOS 26.0, *) {
                ToolbarItem(placement: .primaryAction) {
                    Picker("View", selection: $showsPreview) {
                        Label("Edit", systemImage: "long.text.page.and.pencil").tag(false)
                        Label("Preview", systemImage: "eye").tag(true)
                    }
                    .pickerStyle(.segmented)
                    .labelStyle(.iconOnly)
                }
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
