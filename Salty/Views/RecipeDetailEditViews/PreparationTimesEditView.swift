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
    
    var body: some View {
        VStack {
            List(selection: $selectedIndex) {
                ForEach(Array(recipe.preparationTimes.enumerated()), id: \.element.id) { index, preparationTime in
                    HStack {
                        Label("\(preparationTime.type): \(preparationTime.timeString)", systemImage: "clock")
                        Spacer()
                    }
                    .tag(index)
                }
                .onDelete { indexSet in
                    try? database.write { db in
                        for index in indexSet.sorted(by: >) {
                            recipe.preparationTimes.remove(at: index)
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
                        recipe.preparationTimes.move(fromOffsets: from, toOffset: to)
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
                if let selectedIndex = selectedIndex, selectedIndex < recipe.preparationTimes.count {
                    PreparationTimeDetailEditView(
                        preparationTime: Binding(
                            get: { recipe.preparationTimes[selectedIndex] },
                            set: { newValue in
                                recipe.preparationTimes[selectedIndex] = newValue
                                try? database.write { db in
                                    try Recipe.upsert(Recipe.Draft(recipe))
                                        .execute(db)
                                }
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
                try? database.write { db in
                    recipe.preparationTimes.append(PreparationTime(
                        id: UUID().uuidString,
                        type: "New Time",
                        timeString: "0 minutes"
                    ))
                    try Recipe.upsert(Recipe.Draft(recipe))
                        .execute(db)
                }
                // Select the newly added item
                selectedIndex = recipe.preparationTimes.count - 1
            } label: {
                Label("Add Preparation Time", systemImage: "plus")
            }
            .padding()
        }
        .frame(minWidth: 400, minHeight: 400)
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

struct PreparationTimesEditView_Previews: PreviewProvider {
    static var previews: some View {
        let recipe = try! prepareDependencies {
            $0.defaultDatabase = try Salty.appDatabase()
            return try $0.defaultDatabase.read { db in
                try Recipe.all.fetchOne(db)!
            }
        }
        Group {
            PreparationTimesEditView(recipe: .constant(recipe))
        }
    }
}
