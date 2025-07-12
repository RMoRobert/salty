//
//  DirectionsView.swift
//  Salty
//
//  Created by Robert on 5/29/23.
//

import SwiftUI

struct DirectionsEditView: View {
    @Binding var recipe: Recipe
    @State private var selectedIndex: Int? = nil
    @State private var editingDirections: [Direction] = []
    @State private var hasChanges: Bool = false
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack {
            List(selection: $selectedIndex) {
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
                }
                .onDelete { indexSet in
                    for index in indexSet.sorted(by: >) {
                        editingDirections.remove(at: index)
                    }
                    hasChanges = true
                    // Clear selection if deleted item was selected
                    if let selectedIndex = selectedIndex, indexSet.contains(selectedIndex) {
                        self.selectedIndex = nil
                    }
                }
                .onMove { from, to in
                    editingDirections.move(fromOffsets: from, toOffset: to)
                    hasChanges = true
                }
            }
            #if os(macOS)
            .listStyle(.inset(alternatesRowBackgrounds: true))
            #endif
            
            // Detail editor
            VStack {
                if let selectedIndex = selectedIndex, selectedIndex < editingDirections.count {
                    DirectionDetailEditView(
                        direction: Binding(
                            get: { editingDirections[selectedIndex] },
                            set: { newValue in
                                editingDirections[selectedIndex] = newValue
                                hasChanges = true
                            }
                        )
                    )
                } else {
                    Text("Select a step to edit")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(minHeight: 120, idealHeight: 150)
            .padding()
            
            // Add button
            Button {
                editingDirections.append(Direction(
                    id: UUID().uuidString,
                    isHeading: false,
                    text: "New step"
                ))
                hasChanges = true
                // Select the newly added item
                selectedIndex = editingDirections.count - 1
            } label: {
                Label("Add Step", systemImage: "plus")
            }
            .buttonStyle(.bordered)
            .padding()
        }
        .onAppear {
            editingDirections = recipe.directions
        }
        .onChange(of: editingDirections) { _, _ in
            recipe.directions = editingDirections
        }
        #if os(macOS)
        .frame(minWidth: 500, minHeight: 500)
        #endif
    }
}

struct DirectionDetailEditView: View {
    @Binding var direction: Direction
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Edit Direction")
                .font(.headline)
            
            Toggle("Is Heading", isOn: Binding(
                get: { direction.isHeading ?? false },
                set: { direction.isHeading = $0 }
            ))
            .padding(.bottom, 8)
            
            VStack(alignment: .leading, spacing: 8) {
                Text(direction.isHeading == true ? "Heading Text:" : "Step Text:")
                TextField(direction.isHeading == true ? "Heading" : "Step text", text: $direction.text, axis: .vertical)
                    .lineLimit(4...12)
                    .frame(minHeight: 60)
                #if os(iOS)
                .textFieldStyle(.roundedBorder)
                #endif
            }
        }
        .padding()
    }
}



#Preview {
    DirectionsEditView(recipe: .constant(SampleData.sampleRecipes[0]))
}
