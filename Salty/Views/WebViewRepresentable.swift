//
//  WebViewRepresentable.swift
//  Salty
//
//  Created by Robert on 7/13/25.
//

#if os(macOS)
import SwiftUI
import WebViewKit


import WebKit

struct WebViewRepresentable: NSViewRepresentable {
    let url: String
    @Binding var coordinator: WebViewCoordinator?
    let onNavigationStateChange: (Bool, Bool, Bool) -> Void
    let onURLChange: (String) -> Void
    
    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        
        let coord = WebViewCoordinator(
            webView: webView,
            onNavigationStateChange: onNavigationStateChange,
            onURLChange: onURLChange
        )
        
        webView.navigationDelegate = coord
        
        // Update the binding on the main thread
        DispatchQueue.main.async {
            self.coordinator = coord
        }
        
        print("🌐 WebView initialized with coordinator: \(coord)")
        
        return webView
    }
    
    func updateNSView(_ nsView: WKWebView, context: Context) {
        if let currentURL = nsView.url?.absoluteString, currentURL != url {
            print("🔄 Loading new URL: \(url)")
            if let newURL = URL(string: url) {
                nsView.load(URLRequest(url: newURL))
            } else {
                print("❌ Invalid URL: \(url)")
            }
        }
    }
}

class WebViewCoordinator: NSObject, WKNavigationDelegate {
    private let webView: WKWebView
    private let onNavigationStateChange: (Bool, Bool, Bool) -> Void
    private let onURLChange: (String) -> Void
    
    init(webView: WKWebView, onNavigationStateChange: @escaping (Bool, Bool, Bool) -> Void, onURLChange: @escaping (String) -> Void) {
        self.webView = webView
        self.onNavigationStateChange = onNavigationStateChange
        self.onURLChange = onURLChange
        super.init()
        
        // Load initial URL
        if let url = URL(string: "https://www.google.com") {
            webView.load(URLRequest(url: url))
        }
    }
    
    func goBack() {
        webView.goBack()
    }
    
    func goForward() {
        webView.goForward()
    }
    
    func reload() {
        webView.reload()
    }
    
    func getSelectedText(completion: @escaping (String?) -> Void) {
        print("🔍 Getting selected text from webView")
        webView.evaluateJavaScript("window.getSelection().toString()") { result, error in
            if let error = error {
                print("❌ JavaScript error: \(error)")
                completion(nil)
                return
            }
            
            if let text = result as? String {
                print("✅ Selected text from JS: '\(text)'")
                completion(text)
            } else {
                print("❌ No text result from JavaScript")
                completion(nil)
            }
        }
    }
    
    // MARK: - WKNavigationDelegate
    
    func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
        updateNavigationState()
    }
    
    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        updateNavigationState()
        if let url = webView.url?.absoluteString {
            onURLChange(url)
        }
    }
    
    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        updateNavigationState()
    }
    
    private func updateNavigationState() {
        onNavigationStateChange(webView.canGoBack, webView.canGoForward, webView.isLoading)
    }
}

#endif 
