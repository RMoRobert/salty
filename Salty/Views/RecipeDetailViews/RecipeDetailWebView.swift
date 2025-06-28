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
        WebView(htmlString: recipe.asHtml)
    }
}


struct RecipeDetailWebView_Previews: PreviewProvider {
    static var previews: some View {
        let recipe = try! prepareDependencies {
            $0.defaultDatabase = try Salty.appDatabase()
            return try $0.defaultDatabase.read { db in
                try Recipe.all.fetchOne(db)!
            }
        }
        Group {
            RecipeDetailWebView(recipe: recipe)
        }
    }
}
