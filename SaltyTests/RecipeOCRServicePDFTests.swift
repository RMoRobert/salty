//
//  RecipeOCRServicePDFTests.swift
//  SaltyTests
//
//  Covers the digital-PDF (embedded text layer) path of RecipeOCRService — the fast, accurate path
//  used for any PDF that already carries selectable text, including multi-page documents. The scanned
//  (render + Vision OCR) fallback isn't unit-tested here since it depends on the Vision engine.
//

import Testing
import Foundation
import CoreGraphics
import CoreText
@testable import Salty

@MainActor
struct RecipeOCRServicePDFTests {

    /// Builds a PDF with a real (selectable) text layer — one CTLine per page.
    private func makeTextPDF(pages: [String]) -> Data {
        let data = NSMutableData()
        let consumer = CGDataConsumer(data: data as CFMutableData)!
        var mediaBox = CGRect(x: 0, y: 0, width: 612, height: 792)
        let ctx = CGContext(consumer: consumer, mediaBox: &mediaBox, nil)!
        let font = CTFontCreateWithName("Helvetica" as CFString, 16, nil)
        for text in pages {
            ctx.beginPDFPage(nil)
            let attributed = NSAttributedString(
                string: text,
                attributes: [NSAttributedString.Key(kCTFontAttributeName as String): font]
            )
            let line = CTLineCreateWithAttributedString(attributed)
            ctx.textPosition = CGPoint(x: 72, y: 700)
            CTLineDraw(line, ctx)
            ctx.endPDFPage()
        }
        ctx.closePDF()
        return data as Data
    }

    @Test func extractsEmbeddedTextFromSinglePagePDF() async {
        let service = RecipeOCRService()
        await service.extractText(fromPDFData: makeTextPDF(pages: ["Grandmas Chocolate Chip Cookies"]))
        #expect(service.error == nil)
        #expect(service.extractedText.contains("Grandmas Chocolate Chip Cookies"))
    }

    @Test func extractsEmbeddedTextFromMultiPagePDFWithSeparators() async {
        let service = RecipeOCRService()
        await service.extractText(fromPDFData: makeTextPDF(pages: ["Page one ingredients list", "Page two cooking directions"]))
        #expect(service.error == nil)
        #expect(service.extractedText.contains("Page one ingredients list"))
        #expect(service.extractedText.contains("Page two cooking directions"))
        #expect(service.extractedText.contains("--- Page 2 ---"))
    }

    @Test func reportsErrorForNonPDFData() async {
        let service = RecipeOCRService()
        await service.extractText(fromPDFData: Data("not a pdf".utf8))
        #expect(service.error == .invalidDocument)
        #expect(service.extractedText.isEmpty)
    }
}
