//
//  PreparationTimesView.swift
//  Salty
//
//  Created by Robert on 5/29/23.
//

#if os(macOS)
import SwiftUI

struct PreparationTimesEditView: View {
    //@Dependency(\.defaultDatabase) private var database
    @Binding var recipe: Recipe
    @State private var selectedIndices: Set<Int> = []
    @State private var editingPreparationTimes: [PreparationTime] = []
    @State private var hasChanges: Bool = false
    @State private var topSectionHeight: CGFloat = 300
    @Environment(\.dismiss) private var dismiss
    
    private func deletePreparationTime(at index: Int) {
        guard index < editingPreparationTimes.count else { return }
        editingPreparationTimes.remove(at: index)
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
    
    var body: some View {
            VSplitView {
                // Top Section
                VStack {
                    preparationTimesList
                    
                    //Add Button
                    HStack {
                        Button {
                            editingPreparationTimes.append(PreparationTime(
                                id: UUID().uuidString,
                                type: "New time",
                                timeString: "0 minutes"
                            ))
                            hasChanges = true
                            selectedIndices = [editingPreparationTimes.count - 1]
                        } label: {
                            Label("Add Preparation Time", systemImage: "plus")
                        }
                        Spacer()
                        Button(role: .destructive) {
                        for index in selectedIndices.sorted(by: >) {
                            deletePreparationTime(at: index)
                        }
                    }
                    label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .disabled(selectedIndices.isEmpty)
                        
                    }
                            }
            .padding()
            .frame(minHeight: 250, idealHeight: 350)
            
            // Bottom Section
                VStack {
                    if selectedIndices.count == 1, let firstSelectedIndex = selectedIndices.min(), firstSelectedIndex < editingPreparationTimes.count {
                        PreparationTimeDetailEditView(
                            preparationTime: selectedPreparationTimeBinding
                        )
                    } else {
                        ContentUnavailableView {
                            Text(selectedIndices.count > 1 ?
                                 "Select a single item to edit" : "Select a time to edit"
                            )
                                .font(.body)
                        }
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .frame(minHeight: 75, idealHeight: 90, maxHeight: 400)
                .padding()
            }
        
        .navigationTitle("Edit Preparation Times")
        .onAppear {
            editingPreparationTimes = recipe.preparationTimes
        }
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Done") {
                    dismiss()
                }
            }
        }
        .onAppear {
            editingPreparationTimes = recipe.preparationTimes
        }
        .onChange(of: editingPreparationTimes) { _, _ in
            recipe.preparationTimes = editingPreparationTimes
        }
        .frame(minWidth: 400, maxWidth: .infinity, 
               minHeight: 400, maxHeight: .infinity)
//        #if os(macOS)
//        .presentationSizing(.fitted)
//        #endif
    }

    
    private var preparationTimesList: some View {
        List(selection: $selectedIndices) {
            ForEach(Array(editingPreparationTimes.enumerated()), id: \.element.id) { index, preparationTime in
                HStack {
                    Label("\(preparationTime.type): \(preparationTime.timeString)", systemImage: "clock")
                    Spacer()
                }
                .tag(index)
            }
            .onDelete { indexSet in
                for index in indexSet.sorted(by: >) {
                    deletePreparationTime(at: index)
                }
            }
            .onMove { from, to in
                editingPreparationTimes.move(fromOffsets: from, toOffset: to)
                hasChanges = true
            }
        }
        .listStyle(.bordered)
        .alternatingRowBackgrounds()
    }
    
    
    private var selectedPreparationTimeBinding: Binding<PreparationTime> {
        Binding(
            get: { 
                if let index = selectedIndices.min(), index < editingPreparationTimes.count {
                    return editingPreparationTimes[index]
                }
                return PreparationTime(id: "", type: "", timeString: "")
            },
            set: { newValue in
                if let index = selectedIndices.min(), index < editingPreparationTimes.count {
                    editingPreparationTimes[index] = newValue
                    hasChanges = true
                }
            }
        )
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
            }
            
            HStack {
                Text("Time:")
                    .frame(width: 60, alignment: .leading)
                TextField("Time", text: $preparationTime.timeString)
            }
        }
    }
}

#Preview {
    PreparationTimesEditView(recipe: .constant(SampleData.sampleRecipes[0]))
}

#endif
