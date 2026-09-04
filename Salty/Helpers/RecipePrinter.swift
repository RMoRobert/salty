//
//  RecipePrinter.swift
//  Salty
//
//  Prints recipes. The job runs in four steps, all on the main actor:
//
//   1. Render each recipe's HTML in an off-screen WKWebView and wait until it is actually ready
//      (web fonts loaded, every image decoded) — fixed delays raced layout and produced blank pages.
//   2. Paginate it into a PDF at the chosen paper size. WebKit does the pagination from the stylesheet's
//      `@page` rule (RecipePrintOptions.printCSS); the platform print APIs are only used to capture it.
//      With shrink-to-fit on, the recipe is re-rendered at a few smaller scales and the first one that
//      saves a page is kept.
//   3. Join the per-recipe PDFs and stamp the header/footer with RecipePdfComposer.
//   4. Hand the finished PDF to the system print panel.
//
//  Rendering to PDF first (rather than printing the web view directly) is what makes headers, page
//  numbers, per-recipe shrink-to-fit, and an exact paper size possible, and it makes iOS and macOS
//  produce the same pages.
//

import Foundation
import OSLog
import WebKit
import SaltyCore

#if os(macOS)
import AppKit
import PDFKit
#else
import UIKit
#endif

/// One recipe to print. `html(scale)` renders the recipe's document at a shrink-to-fit scale (1 = none).
struct RecipePrintJob {
    var headerText: String
    var footerText: String
    var html: (Double) -> String
}

// Resolves when the page is ready to paginate.
private let printReadinessJS = """
await document.fonts.ready;
await Promise.all(Array.from(document.images).map(function (img) {
    return img.complete ? Promise.resolve() : (img.decode ? img.decode().catch(function () {}) : Promise.resolve());
}));
return true;
"""

/// Owns one print job from "render the HTML" to "print panel dismissed". Instances keep themselves alive
/// in `active` for the duration, so callers just fire and forget.
@MainActor
final class RecipePrinter: NSObject, WKNavigationDelegate {
    private static var active: [RecipePrinter] = []

    enum PrintError: Error {
        case pageLoadFailed(Error)
        case noPages
        case noWindow
    }

    private let logger = Logger(subsystem: "Salty", category: "Print")
    private let jobs: [RecipePrintJob]
    private let options: RecipePrintOptions
    private let jobTitle: String
    private let webView: WKWebView
    private var loadContinuation: CheckedContinuation<Void, Error>?
    #if os(macOS)
    /// Off-screen host for the web view; WebKit's print path wants the view in a window.
    private let hostWindow: NSWindow
    #endif

    /// Prints `jobs` as one print job (each recipe starts on its own page) after rendering with `options`.
    /// - Parameter jobTitle: shown in the print queue / used as the default PDF name.
    static func print(jobs: [RecipePrintJob], options: RecipePrintOptions, jobTitle: String) {
        let printer = RecipePrinter(jobs: jobs, options: options, jobTitle: jobTitle)
        active.append(printer)
        Task { await printer.run() }
    }

    private init(jobs: [RecipePrintJob], options: RecipePrintOptions, jobTitle: String) {
        self.jobs = jobs
        self.options = options
        self.jobTitle = jobTitle
        let frame = CGRect(origin: .zero, size: options.pageSize)
        webView = WKWebView(frame: frame, configuration: WKWebViewConfiguration())
        #if os(macOS)
        hostWindow = NSWindow(contentRect: frame, styleMask: [.borderless], backing: .buffered, defer: false)
        hostWindow.isReleasedWhenClosed = false
        hostWindow.contentView = webView
        #endif
        super.init()
        webView.navigationDelegate = self
    }

    private func finish() {
        #if os(macOS)
        hostWindow.contentView = nil
        #else
        webView.removeFromSuperview()
        #endif
        Self.active.removeAll { $0 === self }
    }

    // MARK: - Pipeline

    private func run() async {
        do {
            var sections: [RecipePdfComposer.Section] = []
            for job in jobs {
                let pdf = try await paginate(job)
                sections.append(.init(pdf: pdf, headerText: job.headerText, footerText: job.footerText))
            }
            let document = try RecipePdfComposer.compose(sections: sections, pageSize: options.pageSize,
                                                         sideMargin: RecipePrintOptions.sideMargin,
                                                         stampHeadersAndFooters: options.headerAndFooter)
            logger.info("Composed print job \"\(self.jobTitle)\": \(sections.count) recipe(s), \(document.count) bytes")
            try presentPrintPanel(pdf: document)
        } catch {
            logger.error("Printing failed: \(error.localizedDescription)")
            finish()
        }
    }

    /// Renders one recipe to a paginated PDF, shrinking it when that saves a page and the option is on.
    private func paginate(_ job: RecipePrintJob) async throws -> Data {
        var best = try await renderPDF(html: job.html(1))
        let pages = pageCount(of: best)
        guard options.shrinkToFit, pages > 1 else { return best }
        for scale in RecipePrintOptions.shrinkScales {
            let candidate = try await renderPDF(html: job.html(scale))
            if pageCount(of: candidate) < pages {
                logger.info("Shrink-to-fit: \(pages) → \(self.pageCount(of: candidate)) page(s) at \(scale)")
                best = candidate
                break
            }
        }
        return best
    }

    private func pageCount(of pdf: Data) -> Int {
        guard let provider = CGDataProvider(data: pdf as CFData), let document = CGPDFDocument(provider) else { return 0 }
        return document.numberOfPages
    }

    private func renderPDF(html: String) async throws -> Data {
        try await load(html)
        _ = try? await webView.callAsyncJavaScript(printReadinessJS, arguments: [:], contentWorld: .page)
        let pdf = try await capturePDF()
        guard pageCount(of: pdf) > 0 else { throw PrintError.noPages }
        return pdf
    }

    private func load(_ html: String) async throws {
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            loadContinuation = continuation
            webView.loadHTMLString(html, baseURL: nil)
        }
    }

    // MARK: - WKNavigationDelegate

    func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
        loadContinuation?.resume()
        loadContinuation = nil
    }

    func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
        loadContinuation?.resume(throwing: PrintError.pageLoadFailed(error))
        loadContinuation = nil
    }

    func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
        loadContinuation?.resume(throwing: PrintError.pageLoadFailed(error))
        loadContinuation = nil
    }

    // MARK: - macOS

    #if os(macOS)
    private var captureContinuation: CheckedContinuation<Data, Error>?
    private var captureURL: URL?

    /// Paginates the loaded page into a PDF file via a silent print-to-file operation. The NSPrintInfo
    /// margins are zero because WebKit applies the stylesheet's `@page` margins itself (verified: the two
    /// don't stack, and the AppKit values are otherwise ignored for web content).
    private func capturePDF() async throws -> Data {
        let printInfo = NSPrintInfo()
        printInfo.paperSize = options.pageSize
        printInfo.orientation = options.orientation == .landscape ? .landscape : .portrait
        printInfo.horizontalPagination = .automatic
        printInfo.verticalPagination = .automatic
        printInfo.isHorizontallyCentered = false
        printInfo.isVerticallyCentered = false
        printInfo.topMargin = 0
        printInfo.bottomMargin = 0
        printInfo.leftMargin = 0
        printInfo.rightMargin = 0
        printInfo.jobDisposition = .save
        let url = URL.temporaryDirectory.appending(path: "salty-print-\(UUID().uuidString).pdf")
        printInfo.dictionary()[NSPrintInfo.AttributeKey.jobSavingURL] = url
        captureURL = url

        let operation = webView.printOperation(with: printInfo)
        operation.showsPrintPanel = false
        operation.showsProgressPanel = false
        return try await withCheckedThrowingContinuation { continuation in
            captureContinuation = continuation
            operation.runModal(for: hostWindow, delegate: self,
                               didRun: #selector(captureDidRun(_:success:contextInfo:)), contextInfo: nil)
        }
    }

    /// AppKit calls this on the print operation's own thread for a panel-less job (it trapped the main
    /// actor check on macOS 26), so it only hops back to the main actor.
    @objc nonisolated private func captureDidRun(_ operation: NSPrintOperation, success: Bool, contextInfo: UnsafeMutableRawPointer?) {
        Task { @MainActor in self.finishCapture(success: success) }
    }

    private func finishCapture(success: Bool) {
        defer { captureContinuation = nil; captureURL = nil }
        guard let url = captureURL else { return }
        defer { try? FileManager.default.removeItem(at: url) }
        if success, let data = try? Data(contentsOf: url) {
            captureContinuation?.resume(returning: data)
        } else {
            captureContinuation?.resume(throwing: PrintError.noPages)
        }
    }

    private func presentPrintPanel(pdf: Data) throws {
        let printInfo = NSPrintInfo()
        printInfo.paperSize = options.pageSize
        printInfo.orientation = options.orientation == .landscape ? .landscape : .portrait
        printInfo.topMargin = 0
        printInfo.bottomMargin = 0
        printInfo.leftMargin = 0
        printInfo.rightMargin = 0
        guard let document = PDFDocument(data: pdf),
              let operation = document.printOperation(for: printInfo, scalingMode: .pageScaleNone, autoRotate: false) else {
            throw PrintError.noPages
        }
        operation.jobTitle = jobTitle
        operation.showsPrintPanel = true
        operation.showsProgressPanel = true
        // Paper size and orientation were chosen in the app's own sheet and are baked into the PDF, so
        // they aren't offered again here.
        operation.printPanel.options = [.showsCopies, .showsPageRange, .showsPreview]

        guard let window = NSApplication.shared.keyWindow ?? NSApplication.shared.mainWindow ?? NSApplication.shared.windows.first else {
            throw PrintError.noWindow
        }
        operation.runModal(for: window, delegate: self,
                           didRun: #selector(printOperationDidRun(_:success:contextInfo:)), contextInfo: nil)
    }

    @objc nonisolated private func printOperationDidRun(_ operation: NSPrintOperation, success: Bool, contextInfo: UnsafeMutableRawPointer?) {
        Task { @MainActor in
            self.logger.info("Print operation finished (success: \(success))")
            self.finish()
        }
    }

    // MARK: - iOS

    #else
    private var hostView: UIView? {
        UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }
    }

    /// Paginates the loaded page with the web view's print formatter. The formatter lays out into
    /// `printableRect`, which is the whole sheet here so the stylesheet's `@page` margins are the only
    /// margins (matching macOS).
    private func capturePDF() async throws -> Data {
        guard let host = hostView else { throw PrintError.noWindow }
        if webView.superview == nil {
            // WKWebView only lays out (and prints) while it's in a window; park it out of sight.
            webView.frame = CGRect(origin: CGPoint(x: -20_000, y: 0), size: options.pageSize)
            host.addSubview(webView)
        }
        let paper = CGRect(origin: .zero, size: options.pageSize)
        let renderer = UIPrintPageRenderer()
        renderer.addPrintFormatter(webView.viewPrintFormatter(), startingAtPageAt: 0)
        renderer.setValue(paper, forKey: "paperRect")
        renderer.setValue(paper, forKey: "printableRect")

        let data = NSMutableData()
        UIGraphicsBeginPDFContextToData(data, paper, nil)
        renderer.prepare(forDrawingPages: NSRange(location: 0, length: renderer.numberOfPages))
        for page in 0..<renderer.numberOfPages {
            UIGraphicsBeginPDFPage()
            renderer.drawPage(at: page, in: UIGraphicsGetPDFContextBounds())
        }
        UIGraphicsEndPDFContext()
        return data as Data
    }

    private func presentPrintPanel(pdf: Data) throws {
        let printInfo = UIPrintInfo.printInfo()
        printInfo.outputType = .general
        printInfo.jobName = jobTitle
        printInfo.orientation = options.orientation == .landscape ? .landscape : .portrait

        let controller = UIPrintInteractionController.shared
        controller.printInfo = printInfo
        controller.printingItem = pdf
        controller.showsNumberOfCopies = true
        controller.showsPaperSelectionForLoadedPapers = true

        let completion: UIPrintInteractionController.CompletionHandler = { [weak self] _, completed, error in
            if let error {
                self?.logger.error("Print error: \(error.localizedDescription)")
            } else {
                self?.logger.info("Print \(completed ? "completed" : "cancelled")")
            }
            self?.finish()
        }
        if UIDevice.current.userInterfaceIdiom == .pad, let host = hostView {
            // iPad shows the print sheet as a popover anchored to a rect; the phone form is modal.
            let anchor = CGRect(x: host.bounds.midX, y: host.bounds.midY, width: 1, height: 1)
            controller.present(from: anchor, in: host, animated: true, completionHandler: completion)
        } else {
            controller.present(animated: true, completionHandler: completion)
        }
    }
    #endif
}
