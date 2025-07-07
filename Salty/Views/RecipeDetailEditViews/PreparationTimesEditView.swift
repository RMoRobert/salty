//
//  PreparationTimesView.swift
//  Salty
//
//  Created by Robert on 5/29/23.
//

import SwiftUI
import SharingGRDB

struct PreparationTimesEditView: View {
    @Dependency(\.defaultDatabase) private var database
    @Binding var recipe: Recipe
    @State private var selectedIndex: Int? = nil
    @State private var editingPreparationTimes: [PreparationTime] = []
    @State private var hasChanges: Bool = false
    @Environment(\.dismiss) private var dismiss
    
    var body: some View {
        VStack {
            List(selection: $selectedIndex) {
                ForEach(Array(editingPreparationTimes.enumerated()), id: \.element.id) { index, preparationTime in
                    HStack {
                        Label("\(preparationTime.type): \(preparationTime.timeString)", systemImage: "clock")
                        Spacer()
                    }
                    .tag(index)
                }
                .onDelete { indexSet in
                    for index in indexSet.sorted(by: >) {
                        editingPreparationTimes.remove(at: index)
                    }
                    hasChanges = true
                    // Clear selection if deleted item was selected
                    if let selectedIndex = selectedIndex, indexSet.contains(selectedIndex) {
                        self.selectedIndex = nil
                    }
                }
                .onMove { from, to in
                    editingPreparationTimes.move(fromOffsets: from, toOffset: to)
                    hasChanges = true
                }
            }
            #if os(macOS)
            .listStyle(.inset(alternatesRowBackgrounds: true))
            #endif
            
            // Detail editor
            VStack {
                if let selectedIndex = selectedIndex, selectedIndex < editingPreparationTimes.count {
                    PreparationTimeDetailEditView(
                        preparationTime: Binding(
                            get: { editingPreparationTimes[selectedIndex] },
                            set: { newValue in
                                editingPreparationTimes[selectedIndex] = newValue
                                hasChanges = true
                            }
                        )
                    )
                } else {
                    Text("Select a preparation time to edit")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(minHeight: 100, idealHeight: 120)
            .padding()
            
            // Add button
            Button {
                editingPreparationTimes.append(PreparationTime(
                    id: UUID().uuidString,
                    type: "New Time",
                    timeString: "0 minutes"
                ))
                hasChanges = true
                // Select the newly added item
                selectedIndex = editingPreparationTimes.count - 1
            } label: {
                Label("Add Preparation Time", systemImage: "plus")
            }
            .padding()
        }
        .onAppear {
            editingPreparationTimes = recipe.preparationTimes
        }
        .onChange(of: editingPreparationTimes) { _, _ in
            recipe.preparationTimes = editingPreparationTimes
        }
        #if os(macOS)
        .frame(minWidth: 400, minHeight: 400)
        #endif
    }
}

struct PreparationTimeDetailEditView: View {
    @Binding var preparationTime: PreparationTime
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Edit Preparation Time")
                .font(.headline)
            
            HStack {
                Text("Type:")
                    .frame(width: 60, alignment: .leading)
                TextField("Type", text: $preparationTime.type)
                    .textFieldStyle(.roundedBorder)
            }
            
            HStack {
                Text("Time:")
                    .frame(width: 60, alignment: .leading)
                TextField("Time", text: $preparationTime.timeString)
                    .textFieldStyle(.roundedBorder)
            }
        }
        .padding()
    }
}

//#Preview {
//    PreparationTimesEditView(recipe: .constant(SampleData.sampleRecipes[0]))
//}
