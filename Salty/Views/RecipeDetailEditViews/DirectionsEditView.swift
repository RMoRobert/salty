//
//  DirectionsView.swift
//  Salty
//
//  Created by Robert on 5/29/23.
//

#if os(macOS)

import SwiftUI

struct DirectionsEditView: View {
    @Binding var recipe: Recipe
    @State private var editingDirections: [Direction] = []
    @State private var draggedItem: Direction?
    @State private var dropTargetIndex: Int?
    @State private var scrollToNewItem: String?
    @FocusState private var focusedDirectionID: String?
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        directionsScrollView
            .navigationTitle("Edit Directions")
            .toolbar {
                ToolbarItemGroup(placement: .automatic) {
                    Button {
                        addNewStep()
                    } label: {
                        Label("New Step", systemImage: "plus.circle")
                    }
                    .keyboardShortcut("n", modifiers: [.command])
                    
                    Button {
                        addNewHeading()
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
        .onAppear {
            editingDirections = recipe.directions
        }
        .onDisappear {
            recipe.directions = editingDirections
        }
        .frame(minWidth: 600, idealWidth: 700, maxWidth: 800,
               minHeight: 500, idealHeight: 600, maxHeight: 800)
        #if os(macOS)
        .presentationSizing(.fitted)
        #endif
    }
    
    private var directionsScrollView: some View {
        ScrollViewReader { proxy in
            ScrollView {
                directionsList
                    .padding()
            }
            .onChange(of: scrollToNewItem) { _, newID in
                if let newID = newID {
                    withAnimation {
                        proxy.scrollTo(newID, anchor: .center)
                    }
                    // Set focus after scrolling
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        focusedDirectionID = newID
                        scrollToNewItem = nil
                    }
                }
            }
        }
    }
    
    private var directionsList: some View {
        VStack(spacing: 0) {
            ForEach(editingDirections, id: \.id) { direction in
                if let index = editingDirections.firstIndex(where: { $0.id == direction.id }),
                   index < editingDirections.count {
                    dropIndicator(for: index)
                    directionRow(at: index)
                }
            }
            dropIndicatorAtEnd
        }
    }
    
    @ViewBuilder
    private func dropIndicator(for index: Int) -> some View {
        if let dropTarget = dropTargetIndex, dropTarget == index {
            Rectangle()
                .fill(Color.accentColor)
                .frame(height: 3)
                .padding(.horizontal, 20)
                .transition(.opacity.combined(with: .scale))
        }
    }
    
    @ViewBuilder
    private var dropIndicatorAtEnd: some View {
        let currentCount = editingDirections.count
        if let dropTarget = dropTargetIndex, dropTarget == currentCount, currentCount >= 0 {
            Rectangle()
                .fill(Color.primary)
                .frame(height: 2)
                .padding(.horizontal, 20)
                .transition(.opacity.combined(with: .scale))
        }
    }
    
    @ViewBuilder
    private func directionRow(at index: Int) -> some View {
        // Ensure index is valid before accessing - double check to prevent race conditions
        if index >= 0 && index < editingDirections.count {
            let direction = editingDirections[index]
            // Calculate step number by counting non-heading directions before this index
            let stepNumber = editingDirections.prefix(index).filter { !($0.isHeading ?? false) }.count + 1
            // Alternating background colors for list effect
            let backgroundColor = (index % 2 == 0 || editingDirections.count < 3)
                ? Color.clear
                : Color(nsColor: .tertiarySystemFill)
            DirectionEditRowView(
                direction: $editingDirections[index],
                index: index,
                stepNumber: (direction.isHeading ?? false) ? nil : stepNumber,
                backgroundColor: backgroundColor,
                onAdd: { addStepAfter(index) },
                onDelete: { deleteStep(at: index) },
                onMove: { fromIndex, toIndex in
                    moveStep(from: fromIndex, to: toIndex)
                },
                onDragStart: {
                    draggedItem = direction
                },
                onDragEnd: {
                    draggedItem = nil
                    dropTargetIndex = nil
                },
                onDropTargetChanged: { targetIndex in
                    dropTargetIndex = targetIndex
                }
            )
            .focused($focusedDirectionID, equals: direction.id)
            .id(direction.id)
        }
    }
    
    private func addStepAfter(_ index: Int) {
        let newDirection = Direction(
            id: UUID().uuidString,
            isHeading: false,
            text: "New step"
        )
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            editingDirections.insert(newDirection, at: index + 1)
        }
        scrollToNewItem = newDirection.id
        // Set focus after a brief delay to ensure the view is rendered
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            focusedDirectionID = newDirection.id
        }
    }
    
    private func deleteStep(at index: Int) {
        guard index >= 0 && index < editingDirections.count else { return }
        // Clear or adjust drop target if needed
        if let dropTarget = dropTargetIndex {
            if dropTarget == index {
                // Clear if deleting the drop target itself
                dropTargetIndex = nil
            } else if dropTarget > index {
                // Adjust drop target index if item before it is deleted
                dropTargetIndex = dropTarget - 1
            }
            // If dropTarget < index, no adjustment needed
        }
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            editingDirections.remove(at: index)
        }
    }
    
    private func moveStep(from fromIndex: Int, to toIndex: Int) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            editingDirections.move(fromOffsets: IndexSet(integer: fromIndex), toOffset: toIndex)
        }
    }
    
    private func addNewStep() {
        let newDirection = Direction(
            id: UUID().uuidString,
            isHeading: false,
            text: "New step"
        )
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            editingDirections.append(newDirection)
        }
        scrollToNewItem = newDirection.id
        // Set focus after a brief delay to ensure the view is rendered
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            focusedDirectionID = newDirection.id
        }
    }
    
    private func addNewHeading() {
        let newDirection = Direction(
            id: UUID().uuidString,
            isHeading: true,
            text: "New heading"
        )
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            editingDirections.append(newDirection)
        }
        scrollToNewItem = newDirection.id
        // Set focus after a brief delay to ensure the view is rendered
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            focusedDirectionID = newDirection.id
        }
    }
}

// MARK: - Direction Edit Row View

struct DirectionEditRowView: View {
    @Binding var direction: Direction
    let index: Int
    let stepNumber: Int?
    let backgroundColor: Color
    let onAdd: () -> Void
    let onDelete: () -> Void
    let onMove: (Int, Int) -> Void
    let onDragStart: () -> Void
    let onDragEnd: () -> Void
    let onDropTargetChanged: (Int?) -> Void
    
    @State private var isDragging = false
    @State private var isDropTarget = false
    
    var body: some View {
        HStack(alignment: .center, spacing: 2) {
            if let stepNumber = stepNumber {
                Text("\(stepNumber).")
                    .font(.title2)                    .frame(minWidth: 24, alignment: .trailing)
                    .padding(.trailing, 4)
            } else {
                Spacer()
                    .frame(width: 24)
            }
            
            TextField("Direction", text: $direction.text, axis: .vertical)
                .font(direction.isHeading == true ? .headline : .body)
                .fontWeight(direction.isHeading == true ? .semibold : .regular)
                .lineLimit(3...15)
                .textFieldStyle(.squareBorder)
                //.padding()
            
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
                    .foregroundStyle(Color.accentColor)
                    
                    Button {
                        onDelete()
                    } label: {
                        Label("Delete", systemImage: "minus.circle.fill")
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                    
                    // Drag handle - only this can drag
                    Label("Drag to Move", systemImage: "line.3.horizontal")
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.tertiary)
                        .draggable(String(index)) {
                            Label("Drag to Move", systemImage: "line.3.horizontal")
                                .labelStyle(.iconOnly)
                                .foregroundStyle(.tertiary)
                        }
                        .onDrag {
                            isDragging = true
                            onDragStart()
                            return NSItemProvider(object: String(index) as NSString)
                        }
                }
            }
            .frame(alignment: .center)
        }
        .padding(.vertical, 8)
        .padding(.horizontal, 8)
        .background(backgroundColor)
        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        .opacity(isDragging ? 0.4 : 1.0)
        .scaleEffect(isDragging ? 0.95 : 1.0)
        .animation(.spring, value: isDragging)
        .dropDestination(for: String.self) { draggedIndices, location in
            guard let draggedIndexString = draggedIndices.first,
                  let draggedIndex = Int(draggedIndexString),
                  draggedIndex != index else {
                isDragging = false
                onDragEnd()
                return false
            }
            onMove(draggedIndex, draggedIndex < index ? index + 1 : index)
            isDragging = false
            onDragEnd()
            return true
        } isTargeted: { isTargeted in
            isDropTarget = isTargeted
            onDropTargetChanged(isTargeted ? index : nil)
        }
    }
}

#Preview {
    DirectionsEditView(recipe: .constant(SampleData.sampleRecipes[0]))
}

#endif
