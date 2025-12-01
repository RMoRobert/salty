//
//  VariationsEditView.swift
//  Salty
//
//  Created by Assistant on 1/27/25.
//

#if os(macOS)

import SwiftUI

struct VariationsEditView: View {
    @Binding var recipe: Recipe
    @State private var editingVariations: [Variation] = []
    @State private var draggedItem: Variation?
    @State private var dropTargetIndex: Int?
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
                                addNewVariation()
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
        .onAppear {
            editingVariations = recipe.variations
        }
        .onChange(of: editingVariations) { _, newValue in
            recipe.variations = newValue
        }
        .onDisappear {
            recipe.variations = editingVariations
        }
    }
    
    private var variationsContent: some View {
        ScrollViewReader { proxy in
            Group {
                if showToolbar {
                    // Standalone view - add padding
                    variationsList
                        .padding(.horizontal)
                        .padding(.top)
                } else {
                    // Embedded view - no extra padding
                    variationsList
                }
            }
            .onChange(of: scrollToNewItem) { _, newID in
                if let newID = newID {
                    withAnimation(.easeOut) {
                        proxy.scrollTo(newID, anchor: .center)
                    }
                    // Set focus after scrolling
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        focusedVariationID = newID
                        scrollToNewItem = nil
                    }
                }
            }
        }
    }
    
    private var bottomActionButtons: some View {
        HStack {
            Button {
                addNewVariation()
            } label: {
                Label("New Variation", systemImage: "plus.circle")
            }
            .keyboardShortcut("n", modifiers: [.command])
            
            Spacer()
        }
    }
    
    private var variationsList: some View {
        VStack(spacing: 0) {
            ForEach(editingVariations, id: \.id) { variation in
                if let index = editingVariations.firstIndex(where: { $0.id == variation.id }),
                   index < editingVariations.count {
                    dropIndicator(for: index)
                    variationRow(at: index)
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
        let currentCount = editingVariations.count
        if let dropTarget = dropTargetIndex, dropTarget == currentCount, currentCount >= 0 {
            Rectangle()
                .fill(Color.primary)
                .frame(height: 2)
                .padding(.horizontal, 20)
                .transition(.opacity.combined(with: .scale))
        }
    }
    
    @ViewBuilder
    private func variationRow(at index: Int) -> some View {
        // Ensure index is valid before accessing
        if index >= 0 && index < editingVariations.count {
            let variation = editingVariations[index]
            // Create a safe binding that checks bounds
            let variationBinding = Binding<Variation>(
                get: {
                    guard index >= 0 && index < editingVariations.count else {
                        return variation
                    }
                    return editingVariations[index]
                },
                set: { newValue in
                    guard index >= 0 && index < editingVariations.count else { return }
                    editingVariations[index] = newValue
                }
            )
            VariationEditRowView(
                variation: variationBinding,
                index: index,
                onAdd: { addVariationAfter(index) },
                onDelete: { deleteVariation(at: index) },
                onMove: { fromIndex, toIndex in
                    moveVariation(from: fromIndex, to: toIndex)
                },
                onDragStart: {
                    draggedItem = variation
                },
                onDragEnd: {
                    draggedItem = nil
                    dropTargetIndex = nil
                },
                onDropTargetChanged: { targetIndex in
                    dropTargetIndex = targetIndex
                }
            )
            .focused($focusedVariationID, equals: variation.id)
            .id(variation.id)
        }
    }
    
    private func addVariationAfter(_ index: Int) {
        let newVariation = Variation(
            id: UUID().uuidString,
            variationName: "",
            text: ""
        )
        withAnimation(.easeIn) {
            editingVariations.insert(newVariation, at: index + 1)
        }
        scrollToNewItem = newVariation.id
        // Set focus after a brief delay to ensure the view is rendered
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            focusedVariationID = newVariation.id
        }
    }
    
    private func deleteVariation(at index: Int) {
        guard index >= 0 && index < editingVariations.count else { return }
        // Clear or adjust drop target if needed
        if let dropTarget = dropTargetIndex {
            if dropTarget == index {
                dropTargetIndex = nil
            } else if dropTarget > index {
                dropTargetIndex = dropTarget - 1
            }
        }
        withAnimation(.easeIn) {
            editingVariations.remove(at: index)
        }
    }
    
    private func moveVariation(from fromIndex: Int, to toIndex: Int) {
        withAnimation(.easeIn) {
            editingVariations.move(fromOffsets: IndexSet(integer: fromIndex), toOffset: toIndex)
        }
    }
    
    private func addNewVariation() {
        let newVariation = Variation(
            id: UUID().uuidString,
            variationName: "",
            text: ""
        )
        withAnimation(.easeIn) {
            editingVariations.append(newVariation)
        }
        scrollToNewItem = newVariation.id
        // Set focus after a brief delay to ensure the view is rendered
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            focusedVariationID = newVariation.id
        }
    }
}

// MARK: - Variation Edit Row View

struct VariationEditRowView: View {
    @Binding var variation: Variation
    let index: Int
    let onAdd: () -> Void
    let onDelete: () -> Void
    let onMove: (Int, Int) -> Void
    let onDragStart: () -> Void
    let onDragEnd: () -> Void
    let onDropTargetChanged: (Int?) -> Void
    
    @State private var isDragging = false
    @State private var isDropTarget = false
    
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
                .foregroundStyle(Color.accentColor)
                
                Button {
                    onDelete()
                } label: {
                    Label("Delete", systemImage: "minus.circle.fill")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(.red)
                
                // Drag handle
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
        .padding(.vertical, 8)
        .padding(.horizontal, 4)
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
    VariationsEditView(recipe: .constant(SampleData.sampleRecipes[0]))
}

#endif
