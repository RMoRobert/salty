//
//  DirectionsView.swift
//  Salty
//
//  Created by Robert on 5/29/23.
//

import SaltyCore
#if os(macOS)

import SwiftUI

struct DirectionsEditView: View {
    @Binding var recipe: Recipe
    /// Where a dragged row would land, or nil when nothing is being dragged over the list.
    @State private var dropTarget: RecipeItemListEditor.DropTarget?
    /// A row that was just added: scrolled to and focused, then cleared.
    @State private var scrollToNewItem: String?
    @FocusState private var focusedDirectionID: String?
    @Environment(\.dismiss) private var dismiss

    var showToolbar: Bool = true
    var showBottomButtons: Bool = false

    var body: some View {
        Group {
            if showToolbar {
                // Standalone view with toolbar (for sheet presentation)
                directionsContent
                    .navigationTitle("Edit Directions")
                    .toolbar {
                        ToolbarItemGroup(placement: .automatic) {
                            Button {
                                addStep()
                            } label: {
                                Label("New Step", systemImage: "plus.circle")
                            }
                            .keyboardShortcut("n", modifiers: [.command])

                            Button {
                                addHeading()
                            } label: {
                                Label("New Heading", systemImage: "folder.badge.plus")
                            }
                            .keyboardShortcut("n", modifiers: [.command, .shift])
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
                    directionsContent
                    if showBottomButtons {
                        bottomActionButtons
                            .padding(.top, 4)
                    }
                }
            }
        }
    }

    private var directionsContent: some View {
        ScrollViewReader { proxy in
            directionsList
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
                        focusedDirectionID = newID
                        scrollToNewItem = nil
                    }
                }
        }
    }

    private var bottomActionButtons: some View {
        HStack {
            Button {
                addStep()
            } label: {
                Label("New Step", systemImage: "plus.circle")
            }
            .keyboardShortcut("n", modifiers: [.command])

            Button {
                addHeading()
            } label: {
                Label("New Heading", systemImage: "folder.badge.plus")
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])

            Spacer()
        }
    }

    private var directionsList: some View {
        VStack(spacing: 0) {
            ForEach($recipe.directions) { $direction in
                let id = direction.id
                RecipeListDropIndicator(isActive: dropTarget == .above(id))
                DirectionEditRowView(
                    direction: $direction,
                    stepNumber: RecipeItemListEditor.stepNumber(forDirectionWith: id, in: recipe.directions),
                    isAlternateRow: RecipeItemListEditor.isAlternateRow(id: id, in: recipe.directions),
                    focusedDirectionID: $focusedDirectionID,
                    onAdd: { addStep(below: id) },
                    onDelete: { delete(id: id) },
                    onDrop: { droppedID in move(droppedID, to: .above(id)) },
                    onDropTargetChanged: { isTargeted in setDropTarget(.above(id), isTargeted: isTargeted) }
                )
                .id(id)
            }
            RecipeListEndDropZone(
                isActive: dropTarget == .end,
                onDrop: { droppedID in move(droppedID, to: .end) },
                onDropTargetChanged: { isTargeted in setDropTarget(.end, isTargeted: isTargeted) }
            )
        }
    }

    // MARK: - Editing

    private func addStep(below id: String) {
        withAnimation(.easeIn) {
            scrollToNewItem = RecipeItemListEditor.insert(
                .emptyRow(isHeading: false),
                below: id,
                in: &recipe.directions
            )
        }
    }

    private func addStep() {
        append(.emptyRow(isHeading: false))
    }

    private func addHeading() {
        append(.emptyRow(isHeading: true))
    }

    private func append(_ direction: Direction) {
        withAnimation(.easeIn) {
            scrollToNewItem = RecipeItemListEditor.append(direction, to: &recipe.directions)
        }
    }

    private func delete(id: String) {
        withAnimation(.easeIn) {
            RecipeItemListEditor.delete(id: id, from: &recipe.directions)
        }
    }

    private func move(_ id: String, to target: RecipeItemListEditor.DropTarget) -> Bool {
        var moved = false
        withAnimation(.easeIn) {
            moved = RecipeItemListEditor.move(id: id, to: target, in: &recipe.directions)
            dropTarget = nil
        }
        return moved
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

// MARK: - Direction Edit Row View

struct DirectionEditRowView: View {
    @Binding var direction: Direction
    let stepNumber: Int?
    let isAlternateRow: Bool
    var focusedDirectionID: FocusState<String?>.Binding
    let onAdd: () -> Void
    let onDelete: () -> Void
    /// Returns whether the drop was accepted.
    let onDrop: (String) -> Bool
    let onDropTargetChanged: (Bool) -> Void

    private var directionDragPreview: some View {
        HStack(alignment: .center, spacing: 8) {
            if let stepNumber {
                Text("\(stepNumber).")
                    .font(.headline)
                    .foregroundStyle(.secondary)
            }

            Text(direction.text)
                .font(direction.isHeadingRow ? .headline : .body)
                .fontWeight(direction.isHeadingRow ? .semibold : .regular)
                .lineLimit(2)
                .multilineTextAlignment(.leading)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(.regularMaterial)
                .shadow(color: .black.opacity(0.2), radius: 8, x: 0, y: 4)
        )
        .frame(maxWidth: 300)
    }

    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            if let stepNumber {
                Text("\(stepNumber).")
                    .font(.title2)
                    .frame(minWidth: 18, alignment: .trailing)
                    .padding(.trailing, 4)
                    .foregroundStyle(.secondary)
            } else {
                Spacer()
                    .frame(width: 18)
            }

            TextField(direction.isHeadingRow ? "Heading Name" : "Direction text", text: $direction.text, axis: .vertical)
                .font(direction.isHeadingRow ? .headline : .body)
                .fontWeight(direction.isHeadingRow ? .semibold : .regular)
                .lineLimit(direction.isHeadingRow ? 1...2 : 3...13)
                .textFieldStyle(.squareBorder)
                .focused(focusedDirectionID, equals: direction.id)

            Spacer()
                .frame(width: 2)

            // Action buttons - centered vertically
            VStack {
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

                    // Drag handle - only this can drag. The payload is the row's id, so a drop can
                    // tell a real row from a stray text drag and never acts on a stale index.
                    Label("Drag to Move", systemImage: "line.3.horizontal")
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.tertiary)
                        .draggable(direction.id) {
                            directionDragPreview
                        }
                }
            }
            .frame(alignment: .center)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 8)
        .background(isAlternateRow ? Color(nsColor: .tertiarySystemFill) : .clear)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
        .dropDestination(for: String.self) { droppedIDs, _ in
            guard let droppedID = droppedIDs.first else { return false }
            return onDrop(droppedID)
        } isTargeted: { isTargeted in
            onDropTargetChanged(isTargeted)
        }
    }
}

#Preview {
    DirectionsEditView(recipe: .constant(SampleData.sampleRecipes[0]))
}

#endif
