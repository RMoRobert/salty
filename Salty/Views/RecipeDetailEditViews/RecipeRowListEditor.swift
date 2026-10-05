//
//  RecipeRowListEditor.swift
//  Salty
//
//  The list behind the five editable recipe lists -- ingredients, directions, notes, preparation
//  times, variations. Each editor used to carry its own copy of the drop indicators and end zone, the
//  width measurement for the drag preview, the move/delete plumbing, the focus-after-add timer and a
//  `ScrollViewReader` that had no scroll view to read, so a standalone editor clipped a long list.
//  This owns all of that once; an editor supplies its rows and the buttons that add to them.
//
//  Rows are addressed by id throughout, through `RecipeItemListEditor`, which also holds the tested
//  reorder rules.
//

import SwiftUI

struct RecipeRowListEditor<Item: RecipeEditableRow, Row: View>: View {
    @Binding var items: [Item]
    /// The row that was just added, by whoever added it: an editor's own button, or a row's "+".
    /// The list scrolls to it, puts the keyboard in it, and clears this.
    @Binding var newRowID: String?
    /// A standalone editor (a sheet) scrolls itself and pads its content; an embedded one sits in
    /// the host's scroll view and takes the host's padding.
    var isStandalone = false
    /// The blank row a row's own "+" inserts below it.
    let newRow: () -> Item
    @ViewBuilder let row: (Binding<Item>, RecipeRowContext) -> Row

    /// The list's own width, measured so a dragged row's preview can match it.
    @State private var listWidth: CGFloat = 0
    /// Where a dragged row would land, or nil when nothing is being dragged over the list.
    @State private var dropTarget: RecipeItemListEditor.DropTarget?
    @State private var scrollPosition = ScrollPosition(idType: String.self)
    @FocusState private var focusedRowID: String?

    var body: some View {
        VStack(spacing: 0) {
            ForEach(items) { item in
                let id = item.id
                RecipeListDropIndicator(isActive: dropTarget == .above(id))
                row(RecipeItemListEditor.binding(for: id, in: $items, fallback: item), context(for: item))
                    .dropDestination(for: String.self) { droppedIDs, _ in
                        guard let droppedID = droppedIDs.first else { return false }
                        return move(droppedID, to: .above(id))
                    } isTargeted: { isTargeted in
                        setDropTarget(.above(id), isTargeted: isTargeted)
                    }
            }
            RecipeListEndDropZone(
                isActive: dropTarget == .end,
                onDrop: { droppedID in move(droppedID, to: .end) },
                onDropTargetChanged: { isTargeted in setDropTarget(.end, isTargeted: isTargeted) }
            )
        }
        .scrollTargetLayout()
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { width in
            listWidth = width
        }
        .modifier(StandaloneScrolling(isEnabled: isStandalone, position: $scrollPosition))
        .task(id: newRowID) {
            await revealNewRow()
        }
    }

    private func context(for item: Item) -> RecipeRowContext {
        let id = item.id
        let index = items.firstIndex { $0.id == id }
        return RecipeRowContext(
            id: id,
            isAlternateRow: RecipeItemListEditor.isAlternateRow(id: id, in: items),
            canMoveUp: index.map { $0 > 0 } ?? false,
            canMoveDown: index.map { $0 < items.count - 1 } ?? false,
            listWidth: listWidth,
            focus: $focusedRowID,
            addBelow: { addRow(below: id) },
            delete: { delete(id: id) },
            moveUp: { moveUp(id: id) },
            moveDown: { moveDown(id: id) }
        )
    }

    // MARK: - Revealing a new row

    /// Scrolls to and focuses the row named by `newRowID`.
    ///
    /// Runs from `task(id:)`, which starts after the update that set the id -- the same update that
    /// inserted the row -- is committed. That is still too early for the focus to land: on macOS the
    /// row's text field is an `NSTextField` that only comes into being in the layout pass that
    /// follows, and a focus request with nothing to receive it is dropped (verified: without the
    /// wait, focus stayed where it was). So the one wait the five editors used to make each lives
    /// here. A tenth of a second covers a layout pass and is short enough not to be felt.
    private func revealNewRow() async {
        guard let id = newRowID else { return }
        try? await Task.sleep(for: .milliseconds(100))
        guard !Task.isCancelled else { return }
        if isStandalone {
            withAnimation(.easeOut) {
                scrollPosition.scrollTo(id: id, anchor: .center)
            }
        }
        focusedRowID = id
        newRowID = nil
    }

    // MARK: - Editing

    private func addRow(below id: String) {
        withAnimation(.easeIn) {
            newRowID = RecipeItemListEditor.insert(newRow(), below: id, in: &items)
        }
    }

    private func delete(id: String) {
        _ = withAnimation(.easeIn) {
            RecipeItemListEditor.delete(id: id, from: &items)
        }
    }

    private func move(_ id: String, to target: RecipeItemListEditor.DropTarget) -> Bool {
        var moved = false
        withAnimation(.snappy) {
            moved = RecipeItemListEditor.move(id: id, to: target, in: &items)
            dropTarget = nil
        }
        return moved
    }

    private func moveUp(id: String) -> Bool {
        withAnimation(.snappy) {
            RecipeItemListEditor.moveUp(id: id, in: &items)
        }
    }

    private func moveDown(id: String) -> Bool {
        withAnimation(.snappy) {
            RecipeItemListEditor.moveDown(id: id, in: &items)
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

/// Wraps the list in a scroll view of its own when the editor stands alone.
private struct StandaloneScrolling: ViewModifier {
    let isEnabled: Bool
    @Binding var position: ScrollPosition

    func body(content: Content) -> some View {
        if isEnabled {
            ScrollView {
                content
                    .padding(.horizontal)
                    .padding(.top)
            }
            .scrollPosition($position)
        } else {
            content
        }
    }
}

