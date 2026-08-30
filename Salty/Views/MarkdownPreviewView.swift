//
//  MarkdownPreviewView.swift
//  Salty
//
//  Created by Robert on 7/25/26.
//

import SwiftUI
import WebViewKit
import SaltyCore

/// Read-only rendering of user-authored Markdown, converted to HTML by `MarkdownToHtml` and shown in
/// a web view; try native if find solution in future, but this is easy for now to get macOS and iOS parity 
struct MarkdownPreviewView: View {
    let text: String

    var body: some View {
        // WebViewKit loads the HTML once on creation, so the .id forces a fresh web view when the
        // content changes (same approach as RecipeDetailWebView).
        WebView(htmlString: MarkdownToHtml.document(markdown: text))
            .id(text.hashValue)
    }
}

#Preview {
    MarkdownPreviewView(text: """
        # Shopping List

        ## Produce
        * [x] Apples
        * [ ] Spinach
        * Carrots — the **good** ones

        Remember to check for *sales*.
        """)
}
