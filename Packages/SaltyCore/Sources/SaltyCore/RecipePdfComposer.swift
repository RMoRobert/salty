//
//  RecipePdfComposer.swift
//  SaltyCore
//
//  Joins one paginated PDF per recipe into a single print job and stamps a header (recipe name) and
//  footer (source on the left, "Page n of m" on the right — numbered per recipe) onto every page.
//
//  WebKit can't do this itself: it doesn't support CSS `@page` margin boxes or page counters, and it
//  doesn't repeat `position: fixed` elements on each printed page (verified on macOS 26). So the recipe
//  is paginated first, then decorated here with Core Graphics, which works identically on both platforms.
//

import Foundation
import CoreGraphics
import CoreText

public enum RecipePdfComposer {

    /// One recipe's paginated PDF plus what its header/footer should say.
    public struct Section: Sendable {
        public var pdf: Data
        public var headerText: String
        public var footerText: String

        public init(pdf: Data, headerText: String, footerText: String = "") {
            self.pdf = pdf
            self.headerText = headerText
            self.footerText = footerText
        }
    }

    public struct Style: Sendable {
        public var fontName: String = "Helvetica"
        public var fontSize: CGFloat = 9
        public var gray: CGFloat = 0.4
        /// Distance from the paper edge to the text baseline.
        public var headerBaselineInset: CGFloat = 30
        public var footerBaselineInset: CGFloat = 26
        public init() {}
    }

    public enum ComposeError: Error {
        case unreadablePDF(sectionIndex: Int)
        case cannotCreateContext
    }

    /// Concatenates `sections` into one PDF of `pageSize` pages. With `stampHeadersAndFooters` the
    /// header/footer strip is drawn in the margins reserved by `RecipePrintOptions.bandedVerticalMargin`.
    public static func compose(sections: [Section], pageSize: CGSize, sideMargin: CGFloat,
                               stampHeadersAndFooters: Bool, style: Style = Style()) throws -> Data {
        let output = NSMutableData()
        guard let consumer = CGDataConsumer(data: output) else { throw ComposeError.cannotCreateContext }
        var mediaBox = CGRect(origin: .zero, size: pageSize)
        guard let context = CGContext(consumer: consumer, mediaBox: &mediaBox, nil) else {
            throw ComposeError.cannotCreateContext
        }

        for (index, section) in sections.enumerated() {
            guard let provider = CGDataProvider(data: section.pdf as CFData),
                  let source = CGPDFDocument(provider), source.numberOfPages > 0 else {
                throw ComposeError.unreadablePDF(sectionIndex: index)
            }
            for pageNumber in 1...source.numberOfPages {
                guard let page = source.page(at: pageNumber) else { continue }
                context.beginPDFPage(nil)
                context.saveGState()
                // Fit the source page into ours; they're the same size in practice, this just guards a mismatch.
                let transform = page.getDrawingTransform(.mediaBox, rect: mediaBox, rotate: 0, preserveAspectRatio: true)
                context.concatenate(transform)
                context.drawPDFPage(page)
                context.restoreGState()

                if stampHeadersAndFooters {
                    let width = pageSize.width - 2 * sideMargin
                    drawText(section.headerText, in: context, style: style,
                             x: sideMargin, y: pageSize.height - style.headerBaselineInset, maxWidth: width, alignRight: false)
                    let pageLabel = "Page \(pageNumber) of \(source.numberOfPages)"
                    let labelWidth = drawText(pageLabel, in: context, style: style,
                                              x: pageSize.width - sideMargin, y: style.footerBaselineInset,
                                              maxWidth: width, alignRight: true)
                    if !section.footerText.isEmpty {
                        drawText(section.footerText, in: context, style: style,
                                 x: sideMargin, y: style.footerBaselineInset,
                                 maxWidth: width - labelWidth - 12, alignRight: false)
                    }
                }
                context.endPDFPage()
            }
        }
        context.closePDF()
        return output as Data
    }

    /// Draws one line of text, truncated with an ellipsis to `maxWidth`. `x` is the left edge, or the
    /// right edge when `alignRight`. Returns the drawn width.
    @discardableResult
    private static func drawText(_ text: String, in context: CGContext, style: Style,
                                 x: CGFloat, y: CGFloat, maxWidth: CGFloat, alignRight: Bool) -> CGFloat {
        guard !text.isEmpty, maxWidth > 0 else { return 0 }
        let font = CTFontCreateWithName(style.fontName as CFString, style.fontSize, nil)
        let color = CGColor(gray: style.gray, alpha: 1)
        let attributes: [NSAttributedString.Key: Any] = [
            .init(kCTFontAttributeName as String): font,
            .init(kCTForegroundColorAttributeName as String): color,
        ]
        let attributed = NSAttributedString(string: text, attributes: attributes)
        var line = CTLineCreateWithAttributedString(attributed)
        if CTLineGetTypographicBounds(line, nil, nil, nil) > maxWidth {
            let ellipsis = CTLineCreateWithAttributedString(NSAttributedString(string: "…", attributes: attributes))
            line = CTLineCreateTruncatedLine(line, maxWidth, .end, ellipsis) ?? line
        }
        let width = CGFloat(CTLineGetTypographicBounds(line, nil, nil, nil))
        context.saveGState()
        context.textMatrix = .identity
        context.textPosition = CGPoint(x: alignRight ? x - width : x, y: y)
        CTLineDraw(line, context)
        context.restoreGState()
        return width
    }
}
