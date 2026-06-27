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
    @Dependency(\.defaultDatabase) private var database

    var body: some View {
        let names = recipe.libraryNames(database: database)
        WebView(htmlString: recipe.asHtmlWithOptions(options: HTMLExportOptions(), theme: theme,
                                                     course: names.course, categories: names.categories, tags: names.tags))
            // WebViewKit loads the HTML once on creation, so recreate it when the theme or content changes
            // (the .id forces a fresh WebView, reloading with the new content).
            .id("\(theme)-\(names.course ?? "")-\(names.categories.joined(separator: ","))-\(names.tags.joined(separator: ","))")
    }
}


#Preview {
    RecipeDetailWebView(recipe: SampleData.sampleRecipes[0])
}
