//
//  PreparationTimesEditView.swift
//  Salty
//
//  Created by Assistant on 1/27/25.
//

import SaltyCore
#if os(macOS)

import SwiftUI

struct PreparationTimesEditView: View {
    @Binding var recipe: Recipe
    /// Where a dragged row would land, or nil when nothing is being dragged over the list.
    @State private var dropTarget: RecipeItemListEditor.DropTarget?
    /// A row that was just added: scrolled to and focused, then cleared.
    @State private var scrollToNewItem: String?
    @FocusState private var focusedPreparationTimeID: String?
    @Environment(\.dismiss) private var dismiss

    var showToolbar: Bool = true
    var showBottomButtons: Bool = false

    var body: some View {
        Group {
            if showToolbar {
                // Standalone view with toolbar (for sheet presentation)
                preparationTimesContent
                    .navigationTitle("Edit Preparation Times")
                    .toolbar {
                        ToolbarItemGroup(placement: .automatic) {
                            Button {
                                addPreparationTime()
                            } label: {
                                Label("New Time", systemImage: "plus.circle")
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
                    preparationTimesContent
                    if showBottomButtons {
                        bottomActionButtons
                            .padding(.top, 4)
                    }
                }
            }
        }
    }

    private var preparationTimesContent: some View {
        ScrollViewReader { proxy in
            preparationTimesList
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
                        focusedPreparationTimeID = newID
                        scrollToNewItem = nil
                    }
                }
        }
    }

    private var bottomActionButtons: some View {
        HStack {
            Button {
                addPreparationTime()
            } label: {
                Label("New Time", systemImage: "plus.circle")
            }
            .keyboardShortcut("n", modifiers: [.command])

            Spacer()
        }
    }

    private var preparationTimesList: some View {
        VStack(spacing: 0) {
            Grid(alignment: .center, horizontalSpacing: 0, verticalSpacing: 0) {
                ForEach(recipe.preparationTimes) { preparationTime in
                    let id = preparationTime.id
                    let row = RecipeItemListEditor.binding(
                        for: id,
                        in: $recipe.preparationTimes,
                        fallback: preparationTime
                    )
                    RecipeListDropIndicator(isActive: dropTarget == .above(id))
                    GridRow(alignment: .center) {
                        // Type field - apply focus directly here
                        TextField("Type (e.g., \"Bake\")", text: row.type)
                            .textFieldStyle(.squareBorder)
                            .focused($focusedPreparationTimeID, equals: id)
                            .modifier(RecipeRowKeyboardReordering(
                                onMoveUp: { moveUp(id: id) },
                                onMoveDown: { moveDown(id: id) }
                            ))

                        // Time field
                        TextField("Time (e.g., \"1 hr, 30 min\")", text: row.timeString)
                            .textFieldStyle(.squareBorder)
                            .gridCellColumns(2)
                            .modifier(RecipeRowKeyboardReordering(
                                onMoveUp: { moveUp(id: id) },
                                onMoveDown: { moveDown(id: id) }
                            ))

                        // Action buttons
                        PreparationTimeActionButtons(
                            preparationTimeID: id,
                            onAdd: { addPreparationTime(below: id) },
                            onDelete: { delete(id: id) },
                            onDrop: { droppedID in move(droppedID, to: .above(id)) },
                            onDropTargetChanged: { isTargeted in setDropTarget(.above(id), isTargeted: isTargeted) }
                        )
                    }
                    .padding(.vertical, 2)
                    .padding(.horizontal, 3)
                    .id(id)
                }
            }
            RecipeListEndDropZone(
                isActive: dropTarget == .end,
                onDrop: { droppedID in move(droppedID, to: .end) },
                onDropTargetChanged: { isTargeted in setDropTarget(.end, isTargeted: isTargeted) }
            )
        }
    }

    // MARK: - Editing

    private func addPreparationTime(below id: String) {
        withAnimation(.easeIn) {
            scrollToNewItem = RecipeItemListEditor.insert(.emptyRow(), below: id, in: &recipe.preparationTimes)
        }
    }

    private func addPreparationTime() {
        withAnimation(.easeIn) {
            scrollToNewItem = RecipeItemListEditor.append(.emptyRow(), to: &recipe.preparationTimes)
        }
    }

    private func delete(id: String) {
        withAnimation(.easeIn) {
            RecipeItemListEditor.delete(id: id, from: &recipe.preparationTimes)
        }
    }

    private func move(_ id: String, to target: RecipeItemListEditor.DropTarget) -> Bool {
        var moved = false
        withAnimation(.easeIn) {
            moved = RecipeItemListEditor.move(id: id, to: target, in: &recipe.preparationTimes)
            dropTarget = nil
        }
        return moved
    }

    private func moveUp(id: String) -> Bool {
        withAnimation(.easeIn) {
            RecipeItemListEditor.moveUp(id: id, in: &recipe.preparationTimes)
        }
    }

    private func moveDown(id: String) -> Bool {
        withAnimation(.easeIn) {
            RecipeItemListEditor.moveDown(id: id, in: &recipe.preparationTimes)
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

// MARK: - Preparation Time Action Buttons

struct PreparationTimeActionButtons: View {
    let preparationTimeID: String
    let onAdd: () -> Void
    let onDelete: () -> Void
    /// Returns whether the drop was accepted.
    let onDrop: (String) -> Bool
    let onDropTargetChanged: (Bool) -> Void

    var body: some View {
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

            // Drag handle. The payload is the row's id, so a drop can tell a real row from a stray
            // text drag and never acts on a stale index.
            Label("Drag to Move", systemImage: "line.3.horizontal")
                .labelStyle(.iconOnly)
                .foregroundStyle(.tertiary)
                .draggable(preparationTimeID) {
                    Label("Drag to Move", systemImage: "line.3.horizontal")
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.tertiary)
                }
        }
        .dropDestination(for: String.self) { droppedIDs, _ in
            guard let droppedID = droppedIDs.first else { return false }
            return onDrop(droppedID)
        } isTargeted: { isTargeted in
            onDropTargetChanged(isTargeted)
        }
    }
}

#Preview {
    PreparationTimesEditView(recipe: .constant(SampleData.sampleRecipes[0]))
}

#endif
