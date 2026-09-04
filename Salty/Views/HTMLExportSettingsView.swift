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
                    HTMLExportOptionToggles(options: $options)
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

