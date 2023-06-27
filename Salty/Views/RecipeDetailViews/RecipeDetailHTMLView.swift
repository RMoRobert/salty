//
//  RecipeDetailView.swift
//  Salty
//
//  Created by Robert on 10/22/22.
//

import SwiftUI
import WebKit
import Combine
import RealmSwift

struct RecipeDetailHTMLView: View {
    @ObservedRealmObject var recipe: Recipe
   
    var body: some View {
        XPWebView(htmlText: recipe.asHtml)
        .frame(minWidth: 300,
               maxWidth: .infinity,
               minHeight: 100,
               maxHeight: .infinity)
    }
}

#if os(macOS)
struct XPWebView: View {
    /*@Binding*/ var htmlText: String
    
    var body: some View {
        MacWebViewWrapper(htmlText: htmlText)
    }
}
struct MacWebViewWrapper: NSViewRepresentable {
    let htmlText: String
    
    func makeNSView(context: Context) -> WKWebView {
        return WKWebView()
    }
    
    func updateNSView(_ nsView: WKWebView, context: Context) {
        nsView.loadHTMLString(htmlText, baseURL: nil)
    }
}
#else
struct XPWebView: UIViewRepresentable {
  /*@Binding*/ var htmlText: String
   
  func makeUIView(context: Context) -> WKWebView {
    return WKWebView()
  }
   
  func updateUIView(_ uiView: WKWebView, context: Context) {
    uiView.loadHTMLString(htmlText, baseURL: nil)
  }
}
#endif

struct RecipeDetailHTMLView_Previews: PreviewProvider {
    static var previews: some View {
        Group {
            RecipeDetailHTMLView(recipe: Recipe())
        }
        
    }    
}
