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
                MarkdownPreviewView(text: viewModel.text)
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
        .task {
            await viewModel.load()
        }
        .onChange(of: viewModel.text) { _, _ in
            viewModel.scheduleSave()
        }
        .onDisappear {
            viewModel.flush()
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
