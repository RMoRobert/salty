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
    @State private var selectedIndices: Set<Int> = []
    @State private var editingDirections: [Direction] = []
    @State private var hasChanges: Bool = false
    @State private var scrollToNewItem: Bool = false
    @Environment(\.dismiss) private var dismiss
    
    private func deleteDirection(at index: Int) {
        guard index < editingDirections.count else { return }
        editingDirections.remove(at: index)
        hasChanges = true
        
        // Update selection indices after deletion
        var newSelection: Set<Int> = []
        for selectedIndex in selectedIndices {
            if selectedIndex < index {
                // Keep indices before the deleted item unchanged
                newSelection.insert(selectedIndex)
            } else if selectedIndex > index {
                // Decrement indices after the deleted item
                newSelection.insert(selectedIndex - 1)
            }
            // Don't add the deleted index
        }
        selectedIndices = newSelection
    }
    
    private var directionsList: some View {
        ScrollViewReader { proxy in
            List(selection: $selectedIndices) {
                ForEach(Array(editingDirections.enumerated()), id: \.element.id) { index, direction in
                    HStack(alignment: .top) {
                        if direction.isHeading != true {
                            Text("\(editingDirections.prefix(index + 1).filter { $0.isHeading != true }.count).")
                                .font(.title2)
                                .fontWeight(.semibold)
                                .frame(width: 30, alignment: .leading)
                        } else {
                            Spacer()
                                .frame(width: 30)
                        }
                        
                        VStack(alignment: .leading, spacing: 4) {
                            if direction.isHeading == true {
                                Text(direction.text)
                                    .fontWeight(.semibold)
                                    .font(.headline)
                            } else {
                                Text(direction.text)
                                    .lineLimit(3)
                            }
                        }
                        Spacer()
                    }
                    .tag(index)
                    .id(index)
                }
                .onDelete { indexSet in
                    for index in indexSet.sorted(by: >) {
                        deleteDirection(at: index)
                    }
                }
                .onMove { from, to in
                    editingDirections.move(fromOffsets: from, toOffset: to)
                    hasChanges = true
                }
            }
            .listStyle(.bordered)
            .alternatingRowBackgrounds()
            .onChange(of: scrollToNewItem) { _, shouldScroll in
                if shouldScroll, let lastIndex = editingDirections.indices.last {
                    withAnimation(.easeInOut(duration: 0.3)) {
                        proxy.scrollTo(lastIndex, anchor: .bottom)
                    }
                    scrollToNewItem = false
                }
            }
        }
    }
    
    var body: some View {
        VSplitView {
                // Top section: List of directions
                VStack {
                    directionsList
                    
                    // Add and Delete buttons
                    HStack {
                        Button {
                            editingDirections.append(Direction(
                                id: UUID().uuidString,
                                isHeading: false,
                                text: "New step"
                            ))
                            hasChanges = true
                            selectedIndices = [editingDirections.count - 1]
                            scrollToNewItem = true
                        } label: {
                            Label("Add Step", systemImage: "plus")
                        }
                        .padding(.trailing)
                        
                        Button {
                            editingDirections.append(Direction(
                                id: UUID().uuidString,
                                isHeading: true,
                                text: "New heading"
                            ))
                            hasChanges = true
                            selectedIndices = [editingDirections.count - 1]
                            scrollToNewItem = true
                        } label: {
                            Label("Add Heading", systemImage: "folder.badge.plus")
                        }
                        .padding(.trailing)
                        
                        Button(role: .destructive) {
                            for index in selectedIndices.sorted(by: >) {
                                deleteDirection(at: index)
                            }
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        .disabled(selectedIndices.isEmpty)
                        
                        Spacer()
                    }
                }
                .padding()
                .frame(minHeight: 250, idealHeight: 350)
                
                // Bottom section: Detail editor
                VStack {
                    if selectedIndices.count == 1, let firstSelectedIndex = selectedIndices.min(), firstSelectedIndex < editingDirections.count {
                        DirectionDetailEditView(
                            direction: Binding(
                                get: { editingDirections[firstSelectedIndex] },
                                set: { newValue in
                                    editingDirections[firstSelectedIndex] = newValue
                                    hasChanges = true
                                }
                            )
                        )
                    } else {
                        ContentUnavailableView {
                            Text(selectedIndices.count > 1 ?
                                 "Select a single item to edit" : "Select a step to edit"
                            )
                                .font(.body)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(minHeight: 75, idealHeight: 90, maxHeight: 400)
                .padding()
            }
            .navigationTitle("Edit Directions")
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        .onAppear {
            editingDirections = recipe.directions
        }
        .onChange(of: editingDirections) { _, _ in
            recipe.directions = editingDirections
        }
        .frame(minWidth: 500, maxWidth: .infinity, 
               minHeight: 500, maxHeight: .infinity)
        #if os(macOS)
        .presentationSizing(.fitted)
        #endif
    }
}

struct DirectionDetailEditView: View {
    @Binding var direction: Direction
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 8) {
                Text(direction.isHeading == true ? "Heading Text:" : "Step Text:")
                TextField(direction.isHeading == true ? "Heading" : "Step text", text: $direction.text, axis: .vertical)
                    .lineLimit(4...12)
                    .frame(minHeight: 60)
            }
        }
        .padding()
    }
}



#Preview {
    DirectionsEditView(recipe: .constant(SampleData.sampleRecipes[0]))
}


#endif
