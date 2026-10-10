//
//  MarkdownPreviewView.swift
//  Salty
//
//  Created by Robert on 7/25/26.
//

import SwiftUI
import WebKit
import SaltyCore

/// Read-only rendering of user-authored Markdown, converted to HTML by `MarkdownToHtml` and shown in
/// a web view; try native if find solution in future, but this is easy for now to get macOS and iOS parity.
/// OS 26+ only (SwiftUI's `WebView`); earlier systems don't offer the preview.
@available(iOS 26.0, macOS 26.0, *)
struct MarkdownPreviewView: View {
    let text: String
    @State private var page = WebPage()

    var body: some View {
        WebView(page)
            // Reloads the same page in place when the text changes.
            .onChange(of: text, initial: true) {
                page.load(html: MarkdownToHtml.document(markdown: text))
            }
    }
}

#Preview {
    if #available(iOS 26.0, macOS 26.0, *) {
        MarkdownPreviewView(text: """
            # Shopping List

            ## Produce
            * [x] Apples
            * [ ] Spinach
            * Carrots — the **good** ones

            Remember to check for *sales*.
            """)
    }
}
