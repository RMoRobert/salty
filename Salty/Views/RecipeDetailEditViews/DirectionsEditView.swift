//
//  DirectionsView.swift
//  Salty
//
//  Created by Robert on 5/29/23.
//

import SwiftUI
import SharingGRDB

struct DirectionsEditView: View {
    @Dependency(\.defaultDatabase) private var database
    @Binding var recipe: Recipe
    @State private var selectedIndex: Int? = nil
    
    var body: some View {
        VStack {
            List(selection: $selectedIndex) {
                ForEach(Array(recipe.directions.enumerated()), id: \.element.id) { index, direction in
                    HStack(alignment: .top) {
                        Text("\(index + 1).")
                            .font(.title2)
                            .fontWeight(.semibold)
                            .frame(width: 30, alignment: .leading)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            if let stepName = direction.stepName, !stepName.isEmpty {
                                Text(stepName)
                                    .fontWeight(.semibold)
                            }
                            Text(direction.text)
                                .lineLimit(3)
                        }
                        Spacer()
                    }
                    .tag(index)
                }
                .onDelete { indexSet in
                    try? database.write { db in
                        for index in indexSet.sorted(by: >) {
                            recipe.directions.remove(at: index)
                        }
                        try Recipe.upsert(Recipe.Draft(recipe))
                            .execute(db)
                    }
                    // Clear selection if deleted item was selected
                    if let selectedIndex = selectedIndex, indexSet.contains(selectedIndex) {
                        self.selectedIndex = nil
                    }
                }
                .onMove { from, to in
                    try? database.write { db in
                        recipe.directions.move(fromOffsets: from, toOffset: to)
                        try Recipe.upsert(Recipe.Draft(recipe))
                            .execute(db)
                    }
                }
            }
            #if os(macOS)
            .listStyle(.inset(alternatesRowBackgrounds: true))
            #endif
            
            // Detail editor
            VStack {
                if let selectedIndex = selectedIndex, selectedIndex < recipe.directions.count {
                    DirectionDetailEditView(
                        direction: Binding(
                            get: { recipe.directions[selectedIndex] },
                            set: { newValue in
                                recipe.directions[selectedIndex] = newValue
                                try? database.write { db in
                                    try Recipe.upsert(Recipe.Draft(recipe))
                                        .execute(db)
                                }
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
                try? database.write { db in
                    recipe.directions.append(Direction(
                        id: UUID().uuidString,
                        stepName: "",
                        text: "New step"
                    ))
                    try Recipe.upsert(Recipe.Draft(recipe))
                        .execute(db)
                }
                // Select the newly added item
                selectedIndex = recipe.directions.count - 1
            } label: {
                Label("Add Step", systemImage: "plus")
            }
            .buttonStyle(.bordered)
            .padding()
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
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Step Name (optional):")
//                    .font(.subheadline)
//                    .fontWeight(.medium)
                TextField("Step name", text: Binding(
                    get: { direction.stepName ?? "" },
                    set: { newValue in
                        direction.stepName = newValue.isEmpty ? nil : newValue
                    }
                ))
#if os(iOS)
.textFieldStyle(.roundedBorder)
#endif
            }
            
            VStack(alignment: .leading, spacing: 8) {
                Text("Step Text:")
//                    .font(.subheadline)
//                    .fontWeight(.medium)
                TextField("Step text", text: $direction.text, axis: .vertical)
                    //.textFieldStyle(.roundedBorder)
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
