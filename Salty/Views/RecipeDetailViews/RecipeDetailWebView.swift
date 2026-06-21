//
//  RecipeDetailWebView.swift
//  Salty
//
//  Created by Robert on 6/15/25.
//

import Foundation
import SwiftUI
import SQLiteData
import WebViewKit

struct RecipeDetailWebView: View {
    @State var recipe: Recipe
    @AppStorage("recipeHtmlTheme") private var theme: RecipeHtmlTheme = .modern

    var body: some View {
        WebView(htmlString: recipe.asHtmlWithOptions(options: HTMLExportOptions(), theme: theme))
            // WebViewKit loads the HTML once on creation, so recreate it when the theme changes
            // (the .id forces a fresh WebView, reloading with the new theme's CSS).
            .id(theme)
    }
}


#Preview {
    RecipeDetailWebView(recipe: SampleData.sampleRecipes[0])
}
