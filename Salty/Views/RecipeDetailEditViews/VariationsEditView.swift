//
//  VariationsEditView.swift
//  Salty
//
//  Created by Assistant on 1/27/25.
//

import SaltyCore
#if os(macOS)

import SwiftUI

struct VariationsEditView: View {
    @Binding var recipe: Recipe
    /// The list's own width, measured so a dragged row's preview can match it.
    @State private var listWidth: CGFloat = 0
    /// Where a dragged row would land, or nil when nothing is being dragged over the list.
    @State private var dropTarget: RecipeItemListEditor.DropTarget?
    /// A row that was just added: scrolled to and focused, then cleared.
    @State private var scrollToNewItem: String?
    @FocusState private var focusedVariationID: String?
    @Environment(\.dismiss) private var dismiss

    var showToolbar: Bool = true
    var showBottomButtons: Bool = false

    var body: some View {
        Group {
            if showToolbar {
                // Standalone view with toolbar (for sheet presentation)
                variationsContent
                    .navigationTitle("Edit Variations")
                    .toolbar {
                        ToolbarItemGroup(placement: .automatic) {
                            Button {
                                addVariation()
                            } label: {
                                Label("New Variation", systemImage: "plus.circle")
                            }
                            .keyboardShortcut("n", modifiers: [.command])
                        }

                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") {
                                dismiss()
                            }
                            .keyboardShortcut(.return, modifiers: [.command])
                        }
                    }
                    .frame(minWidth: 600, idealWidth: 700, maxWidth: 800,
                           minHeight: 500, idealHeight: 600, maxHeight: 800)
                    .presentationSizing(.fitted)
            } else {
                // Embedded view (no toolbar, no frame constraints)
                VStack(spacing: 0) {
                    variationsContent
                    if showBottomButtons {
                        bottomActionButtons
                            .padding(.top, 4)
                    }
                }
            }
        }
    }

    private var variationsContent: some View {
        ScrollViewReader { proxy in
            variationsList
                // Standalone gets its own padding; embedded takes the host's.
                .padding(.horizontal, showToolbar ? nil : 0)
                .padding(.top, showToolbar ? nil : 0)
                .onChange(of: scrollToNewItem) { _, newID in
                    guard let newID else { return }
                    withAnimation(.easeOut) {
                        proxy.scrollTo(newID, anchor: .center)
                    }
                    // Focus once the row has been laid out.
                    Task {
                        try? await Task.sleep(for: .seconds(0.2))
                        focusedVariationID = newID
                        scrollToNewItem = nil
                    }
                }
        }
    }

    private var bottomActionButtons: some View {
        HStack {
            Button {
                addVariation()
            } label: {
                Label("New Variation", systemImage: "plus.circle")
            }
            .keyboardShortcut("n", modifiers: [.command])

            Spacer()
        }
    }

    private var variationsList: some View {
        VStack(spacing: 0) {
            ForEach(recipe.variations) { variation in
                let id = variation.id
                RecipeListDropIndicator(isActive: dropTarget == .above(id))
                VariationEditRowView(
                    variation: RecipeItemListEditor.binding(for: id, in: $recipe.variations, fallback: variation),
                    dragPreviewWidth: listWidth,
                    focusedVariationID: $focusedVariationID,
                    onAdd: { addVariation(below: id) },
                    onDelete: { delete(id: id) },
                    onDrop: { droppedID in move(droppedID, to: .above(id)) },
                    onDropTargetChanged: { isTargeted in setDropTarget(.above(id), isTargeted: isTargeted) },
                    onMoveUp: { moveUp(id: id) },
                    onMoveDown: { moveDown(id: id) }
                )
                .id(id)
            }
            RecipeListEndDropZone(
                isActive: dropTarget == .end,
                onDrop: { droppedID in move(droppedID, to: .end) },
                onDropTargetChanged: { isTargeted in setDropTarget(.end, isTargeted: isTargeted) }
            )
        }
            .onGeometryChange(for: CGFloat.self) { proxy in
                proxy.size.width
            } action: { width in
                listWidth = width
            }
    }

    // MARK: - Editing

    private func addVariation(below id: String) {
        withAnimation(.easeIn) {
            scrollToNewItem = RecipeItemListEditor.insert(.emptyRow(), below: id, in: &recipe.variations)
        }
    }

    private func addVariation() {
        withAnimation(.easeIn) {
            scrollToNewItem = RecipeItemListEditor.append(.emptyRow(), to: &recipe.variations)
        }
    }

    private func delete(id: String) {
        withAnimation(.easeIn) {
            RecipeItemListEditor.delete(id: id, from: &recipe.variations)
        }
    }

    private func move(_ id: String, to target: RecipeItemListEditor.DropTarget) -> Bool {
        var moved = false
        withAnimation(.easeIn) {
            moved = RecipeItemListEditor.move(id: id, to: target, in: &recipe.variations)
            dropTarget = nil
        }
        return moved
    }

    private func moveUp(id: String) -> Bool {
        withAnimation(.easeIn) {
            RecipeItemListEditor.moveUp(id: id, in: &recipe.variations)
        }
    }

    private func moveDown(id: String) -> Bool {
        withAnimation(.easeIn) {
            RecipeItemListEditor.moveDown(id: id, in: &recipe.variations)
        }
    }

    /// Only the row currently being hovered clears the indicator: dragging from one row to the next
    /// reports the new row as targeted before the old one reports that it isn't.
    private func setDropTarget(_ target: RecipeItemListEditor.DropTarget, isTargeted: Bool) {
        if isTargeted {
            dropTarget = target
        } else if dropTarget == target {
            dropTarget = nil
        }
    }
}

// MARK: - Variation Edit Row View

struct VariationEditRowView: View {
    @Binding var variation: Variation
    /// Width of the list, so the drag preview can match it.
    let dragPreviewWidth: CGFloat
    var focusedVariationID: FocusState<String?>.Binding
    let onAdd: () -> Void
    let onDelete: () -> Void
    /// Returns whether the drop was accepted.
    let onDrop: (String) -> Bool
    let onDropTargetChanged: (Bool) -> Void
    /// Each returns whether the row actually moved.
    let onMoveUp: () -> Bool
    let onMoveDown: () -> Bool

    var body: some View {
        HStack {
            VStack {
                HStack {
                    // Icon
                    Image(systemName: "list.star")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    // Variation name field
                    TextField("Variation Name", text: $variation.variationName)
                        .textFieldStyle(.squareBorder)
                        .font(.headline)
                        .focused(focusedVariationID, equals: variation.id)
                        .modifier(RecipeRowKeyboardReordering(onMoveUp: onMoveUp, onMoveDown: onMoveDown))
                }
                HStack {
                    // Icon
                    Image(systemName: "list.star")
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                        .opacity(0)
                    // Text field (multiline)
                    TextField("Text", text: $variation.text, axis: .vertical)
                        .textFieldStyle(.squareBorder)
                        .lineLimit(2...6)
                        .modifier(RecipeRowKeyboardReordering(onMoveUp: onMoveUp, onMoveDown: onMoveDown))
                }
            }
            // Action buttons
            HStack(spacing: 4) {
                Button {
                    onAdd()
                } label: {
                    Label("Add", systemImage: "plus.circle.fill")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(Color.green)

                Button {
                    onDelete()
                } label: {
                    Label("Delete", systemImage: "minus.circle.fill")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(.red)

                // Drag handle. The payload is the row's id, so a drop can tell a real row from a
                // stray text drag and never acts on a stale index.
                Label("Drag to Move", systemImage: "line.3.horizontal")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.tertiary)
                    .draggable(variation.id) {
                        RecipeRowDragPreview(listWidth: dragPreviewWidth, text: variation.variationName, placeholder: "Variation Name")
                    }
            }
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
        .dropDestination(for: String.self) { droppedIDs, _ in
            guard let droppedID = droppedIDs.first else { return false }
            return onDrop(droppedID)
        } isTargeted: { isTargeted in
            onDropTargetChanged(isTargeted)
        }
    }
}

#Preview {
    VariationsEditView(recipe: .constant(SampleData.sampleRecipes[0]))
}

#endif
