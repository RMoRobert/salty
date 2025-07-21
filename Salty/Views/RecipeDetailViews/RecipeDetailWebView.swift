//
//  RecipeDetailWebView.swift
//  Salty
//
//  Created by Robert on 6/15/25.
//

import Foundation
import SwiftUI
import SharingGRDB
import WebViewKit

struct RecipeDetailWebView: View {
    @State var recipe: Recipe
    
    var body: some View {
        let _ = print(recipe.asHtml)
        WebView(htmlString: recipe.asHtml)
    }
}


#Preview {
    RecipeDetailWebView(recipe: SampleData.sampleRecipes[0])
}
