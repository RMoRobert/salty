//
//  RecipeDetailWebView.swift
//  Salty
//
//  Created by Robert on 6/15/25.
//

import Foundation
import SwiftUI
import SQLiteData
import WebKit
import SaltyCore

/// The experimental web-based recipe detail view. OS 26+ only (SwiftUI's `WebView`); the setting that
/// turns it on is hidden on earlier systems.
@available(iOS 26.0, macOS 26.0, *)
struct RecipeDetailWebView: View {
    /// Observed rather than taken as a snapshot, so a saved edit reloads the page (the same query
    /// `RecipeDetailViewModel` uses for the native view).
    @FetchOne private var recipe: Recipe?
    @AppStorage("recipeHtmlTheme") private var theme: RecipeHtmlTheme = .modern
    @Dependency(\.defaultDatabase) private var database
    @State private var page = WebPage()

    init(recipe: Recipe) {
        _recipe = FetchOne(
            wrappedValue: recipe,
            #sql("SELECT \(Recipe.columns) FROM \(Recipe.self) WHERE \(Recipe.id) = \(bind: recipe.id)")
        )
    }

    var body: some View {
        WebView(page)
            // The HTML is built only when the recipe or theme changes, not on every render: it reads
            // the library names from the database and base64-encodes the photo.
            .onChange(of: recipe, initial: true) { loadPage() }
            .onChange(of: theme) { loadPage() }
    }

    private func loadPage() {
        guard let recipe else { return }
        let names = recipe.libraryNames(database: database)
        page.load(html: recipe.asHtmlWithOptions(options: HTMLExportOptions(), theme: theme,
                                                 course: names.course, categories: names.categories, tags: names.tags))
    }
}


#Preview {
    if #available(iOS 26.0, macOS 26.0, *) {
        RecipeDetailWebView(recipe: SampleData.sampleRecipes[0])
    }
}
