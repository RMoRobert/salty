//
//  HTMLExportSettingsView.swift
//  Salty
//
//  Created by Robert on 1/20/25.
//

import SwiftUI
import SaltyCore

struct HTMLExportSettingsView: View {
    @Binding var options: HTMLExportOptions
    @Environment(\.dismiss) private var dismiss
    var onExport: () -> Void
    #if os(macOS)
    let includeSectionsSectionTitle = "Include Sections:"
    #else
    let includeSectionsSectionTitle = "Include Sections"
    #endif
    
    var body: some View {
        NavigationStack {
            Form {
                Section(includeSectionsSectionTitle) {
                    Toggle("Introduction", isOn: $options.includeIntroduction)
                    Toggle("Ingredients", isOn: $options.includeIngredients)
                    Toggle("Directions", isOn: $options.includeDirections)
                    Toggle("Notes", isOn: $options.includeNotes)
                    Toggle("Variations", isOn: $options.includeVariations)
                    Toggle("Preparation Times", isOn: $options.includePreparationTimes)
                    Toggle("Rating", isOn: $options.includeRating)
                    Toggle("Difficulty", isOn: $options.includeDifficulty)
                    Toggle("Image", isOn: $options.includeImage)
                }
            }
            .navigationTitle("HTML Export Options")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #else
                .padding()
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Export") {
                        onExport()
                        dismiss()
                    }
                }
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                }
            }
        }
    }
}

#Preview {
    HTMLExportSettingsView(options: .constant(HTMLExportOptions()), onExport: {})
}

