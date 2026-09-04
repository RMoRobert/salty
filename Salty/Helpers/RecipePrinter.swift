//
//  RecipePrinter.swift
//  Salty
//
//  Prints recipe HTML through an off-screen WKWebView: load the document, wait until it is actually
//  ready (web fonts loaded, every image decoded), then hand it to the platform print system.
//
//  Page layout — paper size, margins, and where breaks may fall — is owned entirely by the stylesheet's
//  @page / @media print rules in SaltyCore's RecipeToHtml. WebKit paginates from those itself and
//  ignores the NSPrintInfo margins/pagination for its own content (verified on macOS 26), so nothing
//  here tries to add to them.
//

import Foundation
import OSLog
import WebKit
import SaltyCore

// Resolves when the page is ready to print. Replaces fixed-delay timers, which raced layout and image
// decoding and produced clipped or blank output.
private let printReadinessJS = """
await document.fonts.ready;
await Promise.all(Array.from(document.images).map(function (img) {
    return img.complete ? Promise.resolve() : (img.decode ? img.decode().catch(function () {}) : Promise.resolve());
}));
return true;
"""

/// Owns one print job from "load the HTML" to "print panel dismissed". Instances keep themselves alive
/// in `active` for the duration, so callers just fire and forget.
@MainActor
final class RecipePrinter: NSObject, WKNavigationDelegate {
    private static var active: [RecipePrinter] = []

    private let logger = Logger(subsystem: "Salty", category: "Print")
    private let webView: WKWebView
    private let jobTitle: String
    private var didStartPrinting = false

    /// Loads `html` and presents the system print panel for it once it has rendered.
    /// - Parameter jobTitle: shown in the print queue / used as the default PDF name.
    static func print(html: String, jobTitle: String) {
        let printer = RecipePrinter(html: html, jobTitle: jobTitle)
        active.append(printer)
    }

    private init(html: String, jobTitle: String) {
        // US Letter at 72 DPI; WebKit re-lays-out to the paper chosen in the print panel anyway.
        webView = WKWebView(frame: CGRect(x: 0, y: 0, width: 612, height: 792), configuration: WKWebViewConfiguration())
        self.jobTitle = jobTitle
        super.init()
        webView.navigationDelegate = self
        logger.info("Loading recipe HTML for printing (\(html.count) characters)")
        webView.loadHTMLString(html, baseURL: nil)
    }

    private func finish() {
        Self.active.removeAll { $0 === self }
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        guard !didStartPrinting else { return }
        didStartPrinting = true
        Task { @MainActor in
            _ = try? await webView.callAsyncJavaScript(printReadinessJS, arguments: [:], contentWorld: .page)
            presentPrintPanel()
        }
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        logger.error("Print page failed to load: \(error.localizedDescription)")
        finish()
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        logger.error("Print page failed to load: \(error.localizedDescription)")
        finish()
    }

    // MARK: - Platform print panels

    #if os(macOS)
    private func presentPrintPanel() {
        // A fresh NSPrintInfo, never the shared one, so print settings don't leak between jobs.
        let printInfo = NSPrintInfo()
        printInfo.orientation = .portrait
        printInfo.horizontalPagination = .automatic
        printInfo.verticalPagination = .automatic
        printInfo.isHorizontallyCentered = false
        printInfo.isVerticallyCentered = false
        // Mirrors the stylesheet's @page margin (0.5in). WebKit paginates from the stylesheet, so these
        // don't stack with it; they only keep the panel's notion of the printable area consistent.
        printInfo.topMargin = 36
        printInfo.bottomMargin = 36
        printInfo.leftMargin = 36
        printInfo.rightMargin = 36

        let operation = webView.printOperation(with: printInfo)
        operation.jobTitle = jobTitle
        operation.showsPrintPanel = true
        operation.showsProgressPanel = true
        operation.printPanel.options.formUnion([.showsPaperSize, .showsOrientation, .showsPreview,
                                                .showsPageRange, .showsCopies, .showsScaling])

        let window = NSApplication.shared.keyWindow ?? NSApplication.shared.mainWindow ?? NSApplication.shared.windows.first
        if let window {
            operation.runModal(for: window, delegate: self,
                               didRun: #selector(printOperationDidRun(_:success:contextInfo:)), contextInfo: nil)
        } else {
            logger.warning("No window to attach the print panel to; running it detached")
            operation.run()
            finish()
        }
    }

    @objc private func printOperationDidRun(_ operation: NSPrintOperation, success: Bool, contextInfo: UnsafeMutableRawPointer?) {
        logger.info("Print operation finished (success: \(success))")
        finish()
    }
    #else
    private func presentPrintPanel() {
        let printInfo = UIPrintInfo.printInfo()
        printInfo.outputType = .general
        printInfo.jobName = jobTitle
        printInfo.orientation = .portrait
        printInfo.duplex = .none

        let controller = UIPrintInteractionController.shared
        controller.printInfo = printInfo
        // viewPrintFormatter() paginates the rendered page and honors the @media print / @page CSS.
        controller.printFormatter = webView.viewPrintFormatter()
        controller.showsNumberOfCopies = true
        controller.showsPaperSelectionForLoadedPapers = true
        controller.present(animated: true) { [weak self] _, completed, error in
            if let error {
                self?.logger.error("Print error: \(error.localizedDescription)")
            } else {
                self?.logger.info("Print \(completed ? "completed" : "cancelled")")
            }
            self?.finish()
        }
    }
    #endif
}
