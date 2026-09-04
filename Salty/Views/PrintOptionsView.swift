//
//  PrintOptionsView.swift
//  Salty
//
//  The sheet shown before printing: what to include, paper, layout, and color. The choices are a
//  RecipePrintOptions value (SaltyCore), which the view model persists between prints.
//

import SwiftUI
import SaltyCore

struct PrintOptionsView: View {
    @Binding var options: RecipePrintOptions
    /// How many recipes the job covers; only affects wording.
    var recipeCount: Int = 1
    var onPrint: () -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            Form {
                Section("Include") {
                    HTMLExportOptionToggles(options: $options.content)
                }
                Section("Paper") {
                    Picker("Paper Size", selection: $options.paperSize) {
                        ForEach(RecipePrintOptions.PaperSize.allCases) { size in
                            Text(size.displayName).tag(size)
                        }
                    }
                    Picker("Orientation", selection: $options.orientation) {
                        ForEach(RecipePrintOptions.Orientation.allCases) { orientation in
                            Text(orientation.displayName).tag(orientation)
                        }
                    }
                    .pickerStyle(.segmented)
                }
                Section {
                    Toggle("Two-Column Ingredients", isOn: $options.twoColumnIngredients)
                    Toggle("Shrink to Fit", isOn: $options.shrinkToFit)
                    Toggle("Header and Footer", isOn: $options.headerAndFooter)
                } header: {
                    Text("Layout")
                } footer: {
                    Text("Shrink to Fit scales \(recipeCount == 1 ? "the recipe" : "each recipe") down slightly (never below \(RecipePrintOptions.minimumShrinkScale, format: .percent)) when that saves a page. The header and footer show the recipe name, source, and page numbers.")
                }
                Section("Color") {
                    Picker("Color", selection: $options.colorMode) {
                        ForEach(RecipePrintOptions.ColorMode.allCases) { mode in
                            Text(mode.displayName).tag(mode)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                }
            }
            .navigationTitle(recipeCount == 1 ? "Print Recipe" : "Print \(recipeCount) Recipes")
            #if os(macOS)
            .formStyle(.grouped)
            .frame(minWidth: 420, minHeight: 560)
            #else
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Print") {
                        onPrint()
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
    PrintOptionsView(options: .constant(RecipePrintOptions()), recipeCount: 1, onPrint: {})
}
