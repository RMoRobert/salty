//
//  RecipeExportMenu.swift
//  Salty
//
//  The export-format menu items shared by the recipe context menu and the File ▸ Export menu, so both
//  always offer the same set of formats. Each caller supplies its own actions: the context menu acts on
//  a single recipe; the File menu acts on the current selection (via notifications).
//

import SwiftUI
import SaltyCore

@ViewBuilder
func recipeExportFormatItems(
    recipeFile: @escaping () -> Void,
    html: @escaping () -> Void,
    jsonLD: @escaping () -> Void
) -> some View {
    Button("Export as Recipe File…", action: recipeFile)
    Button("Export as HTML…", action: html)
    Button("Export as Schema.org JSON-LD…", action: jsonLD)
}
