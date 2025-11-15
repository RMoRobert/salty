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
    @State private var selectedIndices: Set<Int> = []
    @State private var editingVariations: [Variation] = []
    @State private var hasChanges: Bool = false
    @Environment(\.dismiss) private var dismiss
    
    private func deleteVariation(at index: Int) {
        guard index < editingVariations.count else { return }
        editingVariations.remove(at: index)
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
    
    private var variationsList: some View {
        List(selection: $selectedIndices) {
            ForEach(Array(editingVariations.enumerated()), id: \.element.id) { index, variation in
                VStack(alignment: .leading) {
                    if !variation.variationName.isEmpty {
                        Text(variation.variationName)
                            .font(.headline)
                            .fontWeight(.semibold)
                    }
                    Text(variation.text)
                        .font(.body)
                        .foregroundColor(.secondary)
                        .lineLimit(3)
                }
                .tag(index)
            }
            .onDelete { indexSet in
                for index in indexSet.sorted(by: >) {
                    deleteVariation(at: index)
                }
            }
            .onMove { from, to in
                editingVariations.move(fromOffsets: from, toOffset: to)
                hasChanges = true
            }
        }
        .listStyle(.bordered)
        .alternatingRowBackgrounds()
    }
    
    var body: some View {
        VSplitView {
            // Top section: List of variations
            VStack {
                variationsList
                
                // Add and Delete buttons
                HStack {
                    Button {
                        editingVariations.append(Variation(
                            id: UUID().uuidString,
                            variationName: "New variation",
                            text: ""
                        ))
                        hasChanges = true
                        selectedIndices = [editingVariations.count - 1]
                    } label: {
                        Label("Add Variation", systemImage: "plus")
                    }
                    .padding(.trailing)
                    
                    Spacer()
                    
                    Button(role: .destructive) {
                        for index in selectedIndices.sorted(by: >) {
                            deleteVariation(at: index)
                        }
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                    .disabled(selectedIndices.isEmpty)
                }
            }
            .padding()
            .frame(minHeight: 250, idealHeight: 350)
            
            // Bottom section: Detail editor
            VStack {
                if selectedIndices.count == 1, let firstSelectedIndex = selectedIndices.min(), firstSelectedIndex < editingVariations.count {
                    VariationDetailEditView(
                        variation: Binding(
                            get: { editingVariations[firstSelectedIndex] },
                            set: { newValue in
                                editingVariations[firstSelectedIndex] = newValue
                                hasChanges = true
                            }
                        )
                    )
                } else {
                    ContentUnavailableView {
                        Text(selectedIndices.count > 1 ?
                             "Select a single variation to edit text" : "Select a variation to edit"
                        )
                        .font(.body)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .frame(minHeight: 100, idealHeight: 150, maxHeight: 800)
            .padding()
        }
        .navigationTitle("Edit Variations")
        .toolbar {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    dismiss()
                }
            }
        }
        .onAppear {
            editingVariations = recipe.variations
        }
        .onChange(of: editingVariations) { _, _ in
            recipe.variations = editingVariations
        }
        .frame(minWidth: 500, maxWidth: .infinity,
               minHeight: 500, maxHeight: .infinity)
#if os(macOS)
        .presentationSizing(.fitted)
#endif
    }
}

struct VariationDetailEditView: View {
    @Binding var variation: Variation
    
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Edit Variation")
                .font(.headline)
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Variation Name:")
                TextField("Variation name", text: $variation.variationName)
                    .textFieldStyle(.roundedBorder)
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Text:")
                TextEditor(text: $variation.text)
                    .frame(minHeight: 60)
                    .border(Color.secondary.opacity(0.3))
            }
        }
        .padding()
    }
}

#Preview {
    VariationsEditView(recipe: .constant(SampleData.sampleRecipes[0]))
}

#endif

