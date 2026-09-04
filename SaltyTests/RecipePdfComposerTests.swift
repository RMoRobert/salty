//
//  RecipePdfComposerTests.swift
//  SaltyTests
//

import Testing
import Foundation
import CoreGraphics
import SaltyCore

struct RecipePdfComposerTests {

    /// A PDF with `pages` blank pages of `size`.
    private func blankPDF(pages: Int, size: CGSize) -> Data {
        let data = NSMutableData()
        var box = CGRect(origin: .zero, size: size)
        let context = CGContext(consumer: CGDataConsumer(data: data)!, mediaBox: &box, nil)!
        for _ in 0..<pages {
            context.beginPDFPage(nil)
            context.endPDFPage()
        }
        context.closePDF()
        return data as Data
    }

    private func pageCount(_ pdf: Data) -> Int {
        CGPDFDocument(CGDataProvider(data: pdf as CFData)!)!.numberOfPages
    }

    @Test func concatenatesSectionsInOrder() throws {
        let size = CGSize(width: 612, height: 792)
        let sections = [
            RecipePdfComposer.Section(pdf: blankPDF(pages: 2, size: size), headerText: "A"),
            RecipePdfComposer.Section(pdf: blankPDF(pages: 3, size: size), headerText: "B", footerText: "b.example"),
        ]
        let out = try RecipePdfComposer.compose(sections: sections, pageSize: size, sideMargin: 36, stampHeadersAndFooters: true)
        #expect(pageCount(out) == 5)
        let doc = CGPDFDocument(CGDataProvider(data: out as CFData)!)!
        #expect(doc.page(at: 1)!.getBoxRect(.mediaBox).size == size)
    }

    @Test func stampingAddsContentAndSkippingItDoesNot() throws {
        let size = CGSize(width: 595.276, height: 841.89)
        let section = RecipePdfComposer.Section(pdf: blankPDF(pages: 1, size: size), headerText: "Header", footerText: "Footer")
        let plain = try RecipePdfComposer.compose(sections: [section], pageSize: size, sideMargin: 36, stampHeadersAndFooters: false)
        let stamped = try RecipePdfComposer.compose(sections: [section], pageSize: size, sideMargin: 36, stampHeadersAndFooters: true)
        #expect(pageCount(plain) == 1)
        #expect(pageCount(stamped) == 1)
        #expect(stamped.count > plain.count, "stamped pages carry text drawing and an embedded font")
    }

    @Test func unreadableSectionIsReported() {
        let bad = RecipePdfComposer.Section(pdf: Data("not a pdf".utf8), headerText: "x")
        #expect(throws: RecipePdfComposer.ComposeError.self) {
            try RecipePdfComposer.compose(sections: [bad], pageSize: CGSize(width: 612, height: 792),
                                          sideMargin: 36, stampHeadersAndFooters: true)
        }
    }
}
