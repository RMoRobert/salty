//
//  HTMLExportOptionToggles.swift
//  Salty
//
//  The "which sections to include" toggles, shared by the HTML export sheet and the print options sheet.
//

import SwiftUI
import SaltyCore

struct HTMLExportOptionToggles: View {
    @Binding var options: HTMLExportOptions

    var body: some View {
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
