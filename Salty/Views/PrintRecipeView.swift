//
//  PrintRecipeView.swift
//  Salty
//
//  Created by Auto on 12/2/25.
//

import SwiftUI
import WebKit
import OSLog

// Resolves when the page is actually ready to print: web fonts loaded and every image decoded.
// Replaces fixed-delay timers, which raced layout/image decode and produced clipped or blank output.
private let printReadinessJS = """
await document.fonts.ready;
await Promise.all(Array.from(document.images).map(function (img) {
    return img.complete ? Promise.resolve() : (img.decode ? img.decode().catch(function () {}) : Promise.resolve());
}));
return true;
"""

#if os(macOS)
import AppKit
struct PrintRecipeView: NSViewRepresentable {
    let htmlContent: String
    @Binding var isPresented: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(isPresented: $isPresented)
    }

    func makeNSView(context: Context) -> WKWebView {
        // US Letter at 72 DPI; the print operation re-lays-out to the chosen paper anyway.
        let frame = NSRect(x: 0, y: 0, width: 612, height: 792)
        let webView = WKWebView(frame: frame, configuration: WKWebViewConfiguration())
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        webView.loadHTMLString(htmlContent, baseURL: nil)
        return webView
    }

    func updateNSView(_ nsView: WKWebView, context: Context) {}

    class Coordinator: NSObject, WKNavigationDelegate {
        private let logger = Logger(subsystem: "Salty", category: "Print")
        var webView: WKWebView?   // strong ref so the web view outlives the SwiftUI view during printing
        @Binding var isPresented: Bool
        private var didPrint = false

        init(isPresented: Binding<Bool>) {
            _isPresented = isPresented
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard !didPrint else { return }
            didPrint = true
            Task { @MainActor [weak self] in
                _ = try? await webView.callAsyncJavaScript(printReadinessJS, arguments: [:], contentWorld: .page)
                self?.printWebView(webView)
            }
        }

        private func printWebView(_ webView: WKWebView) {
            // Copy the shared info so we don't mutate global print state.
            let printInfo = (NSPrintInfo.shared.copy() as? NSPrintInfo) ?? NSPrintInfo()
            printInfo.orientation = .portrait
            printInfo.horizontalPagination = .automatic
            printInfo.verticalPagination = .automatic
            printInfo.isHorizontallyCentered = false
            printInfo.isVerticallyCentered = false
            // Margins are owned by the HTML's @page rule; zero these so the two don't stack and clip.
            printInfo.topMargin = 0
            printInfo.bottomMargin = 0
            printInfo.leftMargin = 0
            printInfo.rightMargin = 0

            let printOperation = webView.printOperation(with: printInfo)
            printOperation.showsPrintPanel = true
            printOperation.view?.frame = NSRect(x: 0, y: 0, width: 612, height: 792)

            let finish: () -> Void = { [weak self] in
                DispatchQueue.main.async { self?.isPresented = false }
            }
            if let window = webView.window ?? NSApp.mainWindow ?? NSApp.keyWindow {
                printOperation.runModal(for: window, delegate: nil, didRun: nil, contextInfo: nil)
                finish()
            } else {
                printOperation.run()
                finish()
            }
        }
    }
}
#elseif os(iOS)
import UIKit
struct PrintRecipeView: UIViewRepresentable {
    let htmlContent: String
    @Binding var isPresented: Bool

    func makeCoordinator() -> Coordinator {
        Coordinator(isPresented: $isPresented)
    }

    func makeUIView(context: Context) -> WKWebView {
        let webView = WKWebView(frame: .zero, configuration: WKWebViewConfiguration())
        webView.navigationDelegate = context.coordinator
        context.coordinator.webView = webView
        webView.loadHTMLString(htmlContent, baseURL: nil)
        return webView
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    class Coordinator: NSObject, WKNavigationDelegate {
        private let logger = Logger(subsystem: "Salty", category: "Print")
        var webView: WKWebView?
        @Binding var isPresented: Bool
        private var didPrint = false

        init(isPresented: Binding<Bool>) {
            _isPresented = isPresented
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            guard !didPrint else { return }
            didPrint = true
            Task { @MainActor [weak self] in
                _ = try? await webView.callAsyncJavaScript(printReadinessJS, arguments: [:], contentWorld: .page)
                self?.presentPrint(webView)
            }
        }

        private func presentPrint(_ webView: WKWebView) {
            let controller = UIPrintInteractionController.shared
            let info = UIPrintInfo(dictionary: nil)
            info.outputType = .general
            info.jobName = "Recipe"
            controller.printInfo = info
            // viewPrintFormatter() paginates the *rendered* page and honors the @media print / @page CSS.
            controller.printFormatter = webView.viewPrintFormatter()
            controller.present(animated: true) { [weak self] _, _, _ in
                DispatchQueue.main.async { self?.isPresented = false }
            }
        }
    }
}
#endif
