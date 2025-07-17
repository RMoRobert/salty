//
//  WebViewRepresentable.swift
//  Salty
//
//  Created by Robert on 7/13/25.
//

#if os(macOS)
import SwiftUI
import WebKit

enum WebViewContent {
    case url(String)
    case htmlResource(String) // filename in bundle
    case htmlString(String)
}

struct WebViewRepresentable: NSViewRepresentable {
    let content: WebViewContent
    @Binding var coordinator: WebViewCoordinator?
    let onNavigationStateChange: (Bool, Bool, Bool) -> Void
    let onURLChange: (String) -> Void
    
    // Convenience initializer for URL (maintains backward compatibility)
    init(url: String, coordinator: Binding<WebViewCoordinator?>, onNavigationStateChange: @escaping (Bool, Bool, Bool) -> Void, onURLChange: @escaping (String) -> Void) {
        self.content = .url(url)
        self._coordinator = coordinator
        self.onNavigationStateChange = onNavigationStateChange
        self.onURLChange = onURLChange
    }
    
    // New initializer for content
    init(content: WebViewContent, coordinator: Binding<WebViewCoordinator?>, onNavigationStateChange: @escaping (Bool, Bool, Bool) -> Void, onURLChange: @escaping (String) -> Void) {
        self.content = content
        self._coordinator = coordinator
        self.onNavigationStateChange = onNavigationStateChange
        self.onURLChange = onURLChange
    }
    
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
        
        return webView
    }
    
    func updateNSView(_ nsView: WKWebView, context: Context) {
        switch content {
        case .url(let urlString):
            let currentURL = nsView.url?.absoluteString ?? ""
            let isLoading = nsView.isLoading
            
            // Only load if URL is different AND we're not currently loading
            if currentURL != urlString && !isLoading {
                if let newURL = URL(string: urlString) {
                    nsView.load(URLRequest(url: newURL))
                }
            }
            
        case .htmlResource(let filename):
            // Load HTML from bundle resource
            if let htmlPath = Bundle.main.path(forResource: filename, ofType: "html"),
               let htmlContent = try? String(contentsOfFile: htmlPath, encoding: .utf8) {
                nsView.loadHTMLString(htmlContent, baseURL: Bundle.main.bundleURL)
                // Force navigation state update for HTML content since delegate methods may not fire
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                    self.onNavigationStateChange(nsView.canGoBack, nsView.canGoForward, nsView.isLoading)
                }
            }
            
        case .htmlString(let htmlContent):
            // Load HTML from string
            nsView.loadHTMLString(htmlContent, baseURL: nil)
            // Force navigation state update for HTML content since delegate methods may not fire
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                self.onNavigationStateChange(nsView.canGoBack, nsView.canGoForward, nsView.isLoading)
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
        webView.evaluateJavaScript("window.getSelection().toString()") { result, error in
            if error != nil {
                completion(nil)
                return
            }
            
            if let text = result as? String {
                completion(text)
            } else {
                completion(nil)
            }
        }
    }
    
    func getPageHTML(completion: @escaping (String?) -> Void) {
        webView.evaluateJavaScript("document.documentElement.outerHTML") { result, error in
            if error != nil {
                completion(nil)
                return
            }
            
            if let html = result as? String {
                completion(html)
            } else {
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
    
    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        updateNavigationState()
    }
    
    // MARK: - Navigation Policy
    
    func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
        
        // Allow all navigation by default
        decisionHandler(.allow)
    }
    
    func webView(_ webView: WKWebView, decidePolicyFor navigationResponse: WKNavigationResponse, decisionHandler: @escaping (WKNavigationResponsePolicy) -> Void) {
        
        // Allow all responses by default
        decisionHandler(.allow)
    }
    
    func updateNavigationState() {
        onNavigationStateChange(webView.canGoBack, webView.canGoForward, webView.isLoading)
    }
}

#endif 
