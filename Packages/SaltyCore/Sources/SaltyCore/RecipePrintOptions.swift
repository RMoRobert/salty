//
//  RecipePrintOptions.swift
//  SaltyCore
//
//  Everything the print options sheet lets the user choose, and the CSS those choices turn into.
//
//  The pipeline: a recipe is rendered to HTML (RecipeHtmlDocument) with `printCSS()` appended after the
//  theme so it wins, WebKit paginates that HTML into a PDF at `pageSize`, and RecipePdfComposer stamps
//  the header/footer onto each page. Page geometry therefore has to agree between the CSS `@page` rule
//  and the PDF the composer draws — both read it from here.
//

import Foundation

public struct RecipePrintOptions: Codable, Equatable, Sendable {

    public enum PaperSize: String, Codable, CaseIterable, Identifiable, Sendable {
        case letter, legal, a4, a5

        public var id: String { rawValue }

        public var displayName: String {
            switch self {
            case .letter: "US Letter"
            case .legal: "US Legal"
            case .a4: "A4"
            case .a5: "A5"
            }
        }

        /// Portrait dimensions in PostScript points (1/72 in).
        public var portraitSize: CGSize {
            switch self {
            case .letter: CGSize(width: 612, height: 792)
            case .legal: CGSize(width: 612, height: 1008)
            case .a4: CGSize(width: 595.276, height: 841.89)
            case .a5: CGSize(width: 419.528, height: 595.276)
            }
        }

        /// Letter where the locale measures in inches, A4 everywhere else.
        public static func `default`(for locale: Locale = .current) -> PaperSize {
            locale.measurementSystem == .us ? .letter : .a4
        }
    }

    public enum Orientation: String, Codable, CaseIterable, Identifiable, Sendable {
        case portrait, landscape
        public var id: String { rawValue }
        public var displayName: String { self == .portrait ? "Portrait" : "Landscape" }
    }

    public enum ColorMode: String, Codable, CaseIterable, Identifiable, Sendable {
        /// Everything as on screen.
        case color
        /// All text black; the photo keeps its color.
        case blackText
        /// All text black and the photo desaturated.
        case grayscale
        public var id: String { rawValue }
        public var displayName: String {
            switch self {
            case .color: "Color"
            case .blackText: "Black Text"
            case .grayscale: "Grayscale"
            }
        }
    }

    /// Which recipe sections to include (shared with HTML export).
    public var content: HTMLExportOptions
    public var paperSize: PaperSize
    public var orientation: Orientation
    /// Recipe name and page numbers on every page (drawn by RecipePdfComposer, not by CSS).
    public var headerAndFooter: Bool
    /// Ingredients in two columns instead of one long list.
    public var twoColumnIngredients: Bool
    /// Scale the recipe down a little (never below `minimumShrinkScale`) when that saves a page.
    public var shrinkToFit: Bool
    public var colorMode: ColorMode

    public init(content: HTMLExportOptions = HTMLExportOptions(),
                paperSize: PaperSize = .default(),
                orientation: Orientation = .portrait,
                headerAndFooter: Bool = true,
                twoColumnIngredients: Bool = false,
                shrinkToFit: Bool = true,
                colorMode: ColorMode = .color) {
        self.content = content
        self.paperSize = paperSize
        self.orientation = orientation
        self.headerAndFooter = headerAndFooter
        self.twoColumnIngredients = twoColumnIngredients
        self.shrinkToFit = shrinkToFit
        self.colorMode = colorMode
    }

    // MARK: - Page geometry (points)

    /// The smallest scale shrink-to-fit will go to; anything smaller stops being comfortably legible.
    public static let minimumShrinkScale = 0.85
    /// Scales tried, in order, when shrinking; the first one that saves a page wins.
    public static let shrinkScales: [Double] = [0.95, 0.9, 0.85]

    public static let sideMargin: CGFloat = 36          // 0.5 in
    public static let plainVerticalMargin: CGFloat = 36 // 0.5 in
    /// Top/bottom margin when a header/footer occupies the strip above/below the content.
    public static let bandedVerticalMargin: CGFloat = 58 // ~0.8 in

    /// Paper size in the chosen orientation.
    public var pageSize: CGSize {
        let p = paperSize.portraitSize
        return orientation == .portrait ? p : CGSize(width: p.height, height: p.width)
    }

    public var verticalMargin: CGFloat {
        headerAndFooter ? Self.bandedVerticalMargin : Self.plainVerticalMargin
    }

    // MARK: - CSS

    /// Print-only CSS appended after the base stylesheet and theme. `scale` is the shrink-to-fit factor
    /// (1 = none), applied with `zoom` so the whole layout, not just fonts, gets smaller. WebKit paginates
    /// from the `@page` rule here, so it is the single source of truth for paper size and margins.
    public func printCSS(scale: Double = 1) -> String {
        let size = pageSize
        var css = """
        @page {
            size: \(pt(size.width)) \(pt(size.height));
            margin: \(pt(verticalMargin)) \(pt(Self.sideMargin));
        }
        @media print {

        """
        if scale != 1 {
            css += "    html { zoom: \(Self.cssNumber(scale)) !important; }\n"
        }
        switch colorMode {
        case .color:
            break
        case .blackText:
            css += Self.blackTextCSS
        case .grayscale:
            // Text goes black here; the photo is desaturated before it's embedded (see the app's
            // Recipe.htmlPage(database:grayscaleImage:)). A CSS `filter: grayscale(1)` on the <img> is
            // silently dropped by WebKit's print/PDF path (verified on macOS 26), so it can't be done here.
            css += Self.blackTextCSS
        }
        css += "}\n"
        return css
    }

    private static let blackTextCSS = """
        body, body * { color: #000 !important; -webkit-text-fill-color: #000 !important; }
        .recipe-rating-star-filled, .recipe-rating-star-empty { text-shadow: none !important; }

    """

    private func pt(_ value: CGFloat) -> String {
        Self.cssNumber(Double(value)) + "pt"
    }

    /// A number the way CSS wants it: up to 3 decimals, no grouping separators, no locale.
    private static func cssNumber(_ value: Double) -> String {
        let style = FloatingPointFormatStyle<Double>(locale: Locale(identifier: "en_US_POSIX"))
            .precision(.fractionLength(0...3))
            .grouping(.never)
        return value.formatted(style)
    }
}
