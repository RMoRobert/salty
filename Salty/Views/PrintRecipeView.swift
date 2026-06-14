//
//  PrintRecipeView.swift
//  Salty
//
//  Created by Auto on 12/2/25.
//

import SwiftUI
import WebKit
import OSLog

#if os(macOS)
import AppKit
struct PrintRecipeView: NSViewRepresentable {
    let htmlContent: String
    @Binding var isPresented: Bool
    
    func makeCoordinator() -> Coordinator {
        Coordinator(isPresented: $isPresented)
    }
    
    func makeNSView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        // Give the webView a proper frame size for rendering (standard US Letter size in points)
        let frame = NSRect(x: 0, y: 0, width: 612, height: 792) // 8.5" x 11" at 72 DPI
        let webView = WKWebView(frame: frame, configuration: configuration)
        
        // Set the navigation delegate to detect when page is loaded
        webView.navigationDelegate = context.coordinator
        
        // Load the HTML content
        webView.loadHTMLString(htmlContent, baseURL: nil)
        
        context.coordinator.webView = webView
        
        return webView
    }
    
    func updateNSView(_ nsView: WKWebView, context: Context) {
        // No updates needed
    }
    
    class Coordinator: NSObject, WKNavigationDelegate {
        private let logger = Logger(subsystem: "Salty", category: "Print")
        var webView: WKWebView?
        @Binding var isPresented: Bool
        
        init(isPresented: Binding<Bool>) {
            _isPresented = isPresented
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            // Wait for the webView to finish rendering its content
            // We need to wait a bit longer to ensure the frame is properly initialized
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                // Ensure the webView has a proper frame before printing
                if webView.frame.width == 0 || webView.frame.height == 0 {
                    webView.frame = NSRect(x: 0, y: 0, width: 612, height: 792)
                }
                
                // Wait a bit more for rendering to complete
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
                    self.printWebView(webView)
                }
            }
        }
        
        private func printWebView(_ webView: WKWebView) {
            // Ensure webView has a valid frame
            guard webView.frame.width > 0 && webView.frame.height > 0 else {
                logger.error("Error: WebView frame is invalid for printing")
                DispatchQueue.main.async {
                    self.isPresented = false
                }
                return
            }
            
            // Use WKWebView's print method
            let printInfo = NSPrintInfo.shared
            printInfo.orientation = .portrait
            printInfo.verticalPagination = .automatic
            printInfo.horizontalPagination = .automatic
            printInfo.isVerticallyCentered = false
            printInfo.isHorizontallyCentered = false
            
            let printOperation = webView.printOperation(with: printInfo)
            printOperation.showsPrintPanel = true
            
            // Run the print panel
            if let window = NSApp.mainWindow ?? NSApp.keyWindow {
                printOperation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
            } else {
                // Fallback: run without a specific window
                printOperation.run()
            }
            
            // Close the view after printing
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                self.isPresented = false
            }
        }
    }
}
#elseif os(iOS)
// iOS implementation - placeholder for future
struct PrintRecipeView: UIViewRepresentable {
    let htmlContent: String
    @Binding var isPresented: Bool
    
    func makeUIView(context: Context) -> WKWebView {
        let configuration = WKWebViewConfiguration()
        let webView = WKWebView(frame: .zero, configuration: configuration)
        
        // Load the HTML content
        webView.loadHTMLString(htmlContent, baseURL: nil)
        
        return webView
    }
    
    func updateUIView(_ uiView: WKWebView, context: Context) {
        // No updates needed for now
        // TODO: Implement iOS printing when needed
    }
}
#endif

