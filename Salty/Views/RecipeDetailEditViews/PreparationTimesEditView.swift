//
//  PreparationTimesView.swift
//  Salty
//
//  Created by Robert on 5/29/23.
//

#if os(macOS)
import SwiftUI

struct PreparationTimesEditView: View {
    @Binding var recipe: Recipe
    @State private var editingPreparationTimes: [PreparationTime] = []
    @State private var draggedItem: PreparationTime?
    @State private var dropTargetIndex: Int?
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
                                addNewPreparationTime()
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
        .onAppear {
            editingPreparationTimes = recipe.preparationTimes
        }
        .onChange(of: editingPreparationTimes) { _, newValue in
            recipe.preparationTimes = newValue
        }
        .onDisappear {
            recipe.preparationTimes = editingPreparationTimes
        }
    }
    
    private var preparationTimesContent: some View {
        ScrollViewReader { proxy in
            Group {
                if showToolbar {
                    // Standalone view - add padding
                    preparationTimesList
                        .padding(.horizontal)
                        .padding(.top)
                } else {
                    // Embedded view - no extra padding
                    preparationTimesList
                }
            }
            .onChange(of: scrollToNewItem) { _, newID in
                if let newID = newID {
                    withAnimation(.easeOut) {
                        proxy.scrollTo(newID, anchor: .center)
                    }
                    // Set focus after scrolling
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                        focusedPreparationTimeID = newID
                        scrollToNewItem = nil
                    }
                }
            }
        }
    }
    
    private var bottomActionButtons: some View {
        HStack {
            Button {
                addNewPreparationTime()
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
                ForEach(editingPreparationTimes, id: \.id) { preparationTime in
                    if let index = editingPreparationTimes.firstIndex(where: { $0.id == preparationTime.id }),
                       index < editingPreparationTimes.count {
                        dropIndicator(for: index)
                        preparationTimeRow(at: index)
                    }
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
        let currentCount = editingPreparationTimes.count
        if let dropTarget = dropTargetIndex, dropTarget == currentCount, currentCount >= 0 {
            Rectangle()
                .fill(Color.primary)
                .frame(height: 2)
                .padding(.horizontal, 20)
                .transition(.opacity.combined(with: .scale))
        }
    }
    
    @ViewBuilder
    private func preparationTimeRow(at index: Int) -> some View {
        // Ensure index is valid before accessing
        if index >= 0 && index < editingPreparationTimes.count {
            let preparationTime = editingPreparationTimes[index]
            // Create a safe binding that checks bounds
            let preparationTimeBinding = Binding<PreparationTime>(
            get: { 
                    guard index >= 0 && index < editingPreparationTimes.count else {
                        return preparationTime
                    }
                    return editingPreparationTimes[index]
            },
            set: { newValue in
                    guard index >= 0 && index < editingPreparationTimes.count else { return }
                    editingPreparationTimes[index] = newValue
                }
            )
            GridRow(alignment: .center) {
                // Type field - apply focus directly here
                TextField("Type (e.g., \"Bake\")", text: preparationTimeBinding.type)
                    .textFieldStyle(.squareBorder)
                    .focused($focusedPreparationTimeID, equals: preparationTime.id)
                
                // Time field
                TextField("Time (e.g., \"1 hr, 30 min\")", text: preparationTimeBinding.timeString)
                    .textFieldStyle(.squareBorder)
                    .gridCellColumns(2)
                
                // Action buttons
                PreparationTimeActionButtons(
                    index: index,
                    onAdd: { addPreparationTimeAfter(index) },
                    onDelete: { deletePreparationTime(at: index) },
                    onMove: { fromIndex, toIndex in
                        movePreparationTime(from: fromIndex, to: toIndex)
                    },
                    onDragStart: {
                        draggedItem = preparationTime
                    },
                    onDragEnd: {
                        draggedItem = nil
                        dropTargetIndex = nil
                    },
                    onDropTargetChanged: { targetIndex in
                        dropTargetIndex = targetIndex
                    }
                )
            }
            .padding(.vertical, 2)
            .padding(.horizontal, 3)
            .id(preparationTime.id)
        }
    }
    
    private func addPreparationTimeAfter(_ index: Int) {
        let newPreparationTime = PreparationTime(
            id: UUID().uuidString,
            type: "",
            timeString: ""
        )
        withAnimation(.easeIn) {
            editingPreparationTimes.insert(newPreparationTime, at: index + 1)
        }
        scrollToNewItem = newPreparationTime.id
        // Set focus after a brief delay to ensure the view is rendered
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            focusedPreparationTimeID = newPreparationTime.id
        }
    }
    
    private func deletePreparationTime(at index: Int) {
        guard index >= 0 && index < editingPreparationTimes.count else { return }
        // Clear or adjust drop target if needed
        if let dropTarget = dropTargetIndex {
            if dropTarget == index {
                dropTargetIndex = nil
            } else if dropTarget > index {
                dropTargetIndex = dropTarget - 1
            }
        }
        withAnimation(.easeIn) {
            _ = editingPreparationTimes.remove(at: index)
        }
    }
    
    private func movePreparationTime(from fromIndex: Int, to toIndex: Int) {
        withAnimation(.easeIn) {
            editingPreparationTimes.move(fromOffsets: IndexSet(integer: fromIndex), toOffset: toIndex)
        }
    }
    
    private func addNewPreparationTime() {
        let newPreparationTime = PreparationTime(
            id: UUID().uuidString,
            type: "",
            timeString: ""
        )
        withAnimation(.easeIn) {
            editingPreparationTimes.append(newPreparationTime)
        }
        scrollToNewItem = newPreparationTime.id
        // Set focus after a brief delay to ensure the view is rendered
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            focusedPreparationTimeID = newPreparationTime.id
        }
    }
}

// MARK: - Preparation Time Action Buttons

struct PreparationTimeActionButtons: View {
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
    PreparationTimesEditView(recipe: .constant(SampleData.sampleRecipes[0]))
}

#endif
