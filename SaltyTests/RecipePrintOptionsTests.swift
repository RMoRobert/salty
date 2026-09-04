//
//  RecipePrintOptionsTests.swift
//  SaltyTests
//
//  The print options model: page geometry, the CSS it emits, the two-column ingredient ordering it
//  drives, and how it flows into RecipeHtmlDocument.
//

import Testing
import Foundation
import CoreGraphics
import ImageIO
import UniformTypeIdentifiers
@testable import Salty
import SaltyCore

struct RecipePrintOptionsTests {

    // MARK: Page geometry

    @Test func landscapeSwapsPaperDimensions() {
        var options = RecipePrintOptions(paperSize: .a4, orientation: .portrait)
        #expect(options.pageSize.width < options.pageSize.height)
        options.orientation = .landscape
        #expect(options.pageSize.width > options.pageSize.height)
        #expect(options.pageSize.width == RecipePrintOptions.PaperSize.a4.portraitSize.height)
    }

    @Test func headerAndFooterReserveTallerVerticalMargins() {
        let plain = RecipePrintOptions(headerAndFooter: false)
        let banded = RecipePrintOptions(headerAndFooter: true)
        #expect(banded.verticalMargin > plain.verticalMargin)
        #expect(plain.verticalMargin == RecipePrintOptions.plainVerticalMargin)
    }

    @Test func defaultPaperFollowsLocaleMeasurementSystem() {
        #expect(RecipePrintOptions.PaperSize.default(for: Locale(identifier: "en_US")) == .letter)
        #expect(RecipePrintOptions.PaperSize.default(for: Locale(identifier: "de_DE")) == .a4)
        #expect(RecipePrintOptions.PaperSize.default(for: Locale(identifier: "en_GB")) == .a4)
    }

    // MARK: CSS

    @Test func pageRuleCarriesSizeAndMargins() {
        let options = RecipePrintOptions(paperSize: .letter, orientation: .landscape, headerAndFooter: true)
        let css = options.printCSS()
        #expect(css.contains("size: 792pt 612pt;"))
        #expect(css.contains("margin: \(Int(RecipePrintOptions.bandedVerticalMargin))pt \(Int(RecipePrintOptions.sideMargin))pt;"))
        #expect(!css.contains("zoom:"), "no zoom rule at scale 1")
    }

    @Test func metricPaperSizesUseUngroupedDecimalPoints() {
        let css = RecipePrintOptions(paperSize: .a4).printCSS()
        #expect(css.contains("size: 595.276pt 841.89pt;"))
    }

    @Test func shrinkScaleBecomesZoom() {
        let css = RecipePrintOptions().printCSS(scale: 0.9)
        #expect(css.contains("html { zoom: 0.9 !important; }"))
    }

    @Test func colorModesEmitTheirOverrides() {
        #expect(!RecipePrintOptions(colorMode: .color).printCSS().contains("color: #000"))
        let black = RecipePrintOptions(colorMode: .blackText).printCSS()
        #expect(black.contains("color: #000 !important"))
        #expect(!black.contains("grayscale"))
        let gray = RecipePrintOptions(colorMode: .grayscale).printCSS()
        #expect(gray.contains("color: #000 !important"))
        #expect(!gray.contains("filter:"), "WebKit drops CSS image filters when printing; the photo is desaturated in Swift instead")
    }

    // MARK: Two-column ingredient order

    private func recipe(with texts: [String]) -> Recipe {
        var recipe = Recipe(id: "r", name: "R")
        recipe.ingredients = texts.enumerated().map { index, text in
            var ingredient = Ingredient(id: "i\(index)", text: text)
            ingredient.isHeading = text.hasPrefix("#")
            return ingredient
        }
        return recipe
    }

    @Test func singleColumnLeavesOrderAlone() {
        let recipe = recipe(with: ["a", "b", "c"])
        #expect(recipe.ingredientsInColumnReadingOrder(columns: 1).map(\.text) == ["a", "b", "c"])
    }

    @Test func twoColumnsInterleaveSoRowsReadDownColumns() {
        // Five items in two columns = 3 rows: column 1 is a b c, column 2 is d e.
        let recipe = recipe(with: ["a", "b", "c", "d", "e"])
        #expect(recipe.ingredientsInColumnReadingOrder(columns: 2).map(\.text) == ["a", "d", "b", "e", "c"])
    }

    @Test func headingsStayPutAndStartNewGroups() {
        let recipe = recipe(with: ["a", "b", "c", "#Sauce", "d", "e", "f", "g"])
        let order = recipe.ingredientsInColumnReadingOrder(columns: 2).map(\.text)
        #expect(order == ["a", "c", "b", "#Sauce", "d", "f", "e", "g"])
    }

    // MARK: Document integration

    @Test func documentAppendsPrintCSSAfterThemeAndMarksTwoColumnList() {
        var recipe = Recipe(id: "r", name: "Toast")
        recipe.ingredients = [Ingredient(id: "i1", text: "bread"), Ingredient(id: "i2", text: "butter")]
        let page = RecipeHtmlPage(recipe: recipe, imageBase64: nil)
        let options = RecipePrintOptions(paperSize: .a5, twoColumnIngredients: true, colorMode: .grayscale)
        let html = RecipeHtmlDocument.render([page], options: HTMLExportOptions(), theme: .retro, title: "Toast",
                                             printOptions: options, printScale: 0.95)
        #expect(html.contains("recipe-ingredients-list columns-2"))
        #expect(html.contains("zoom: 0.95"))
        guard let themeStart = html.range(of: "--salty-font-body: \"Lucida Grande\""),
              let printStart = html.range(of: "size: 419.528pt 595.276pt;") else {
            Issue.record("theme or print CSS missing"); return
        }
        #expect(themeStart.lowerBound < printStart.lowerBound, "print CSS must come after the theme so it wins")
    }

    @Test func documentWithoutPrintOptionsIsUnchanged() {
        var recipe = Recipe(id: "r", name: "Toast")
        recipe.ingredients = [Ingredient(id: "i1", text: "bread")]
        let html = RecipeHtmlDocument.render([RecipeHtmlPage(recipe: recipe, imageBase64: nil)],
                                             options: HTMLExportOptions(), title: "Toast")
        #expect(!html.contains("class=\"recipe-ingredients-list columns-2\""), "one column unless printing two")
        #expect(html.contains("class=\"recipe-ingredients-list\""))
        #expect(html.contains("size: letter;"), "the base @page rule still applies for exports")
    }

    // MARK: Persistence

    @Test func optionsRoundTripThroughUserDefaults() {
        let defaults = UserDefaults(suiteName: "RecipePrintOptionsTests-\(UUID().uuidString)")!
        defer { defaults.removePersistentDomain(forName: defaults.description) }
        var options = RecipePrintOptions(paperSize: .legal, orientation: .landscape, headerAndFooter: false,
                                         twoColumnIngredients: true, shrinkToFit: false, colorMode: .blackText)
        options.content.includeImage = false
        options.saveToDefaults(defaults)
        #expect(RecipePrintOptions.loadFromDefaults(defaults) == options)
    }

    // MARK: Grayscale photo

    /// A small solid-red JPEG.
    private func redJPEG() -> Data {
        let context = CGContext(data: nil, width: 8, height: 8, bitsPerComponent: 8, bytesPerRow: 0,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.setFillColor(CGColor(red: 1, green: 0, blue: 0, alpha: 1))
        context.fill(CGRect(x: 0, y: 0, width: 8, height: 8))
        let data = NSMutableData()
        let dest = CGImageDestinationCreateWithData(data, UTType.jpeg.identifier as CFString, 1, nil)!
        CGImageDestinationAddImage(dest, context.makeImage()!, nil)
        CGImageDestinationFinalize(dest)
        return data as Data
    }

    private func centerPixel(ofBase64JPEG base64: String) -> (r: UInt8, g: UInt8, b: UInt8) {
        let data = Data(base64Encoded: base64)!
        let image = CGImageSourceCreateImageAtIndex(CGImageSourceCreateWithData(data as CFData, nil)!, 0, nil)!
        var pixel = [UInt8](repeating: 0, count: 4)
        let context = CGContext(data: &pixel, width: 1, height: 1, bitsPerComponent: 8, bytesPerRow: 4,
                                space: CGColorSpaceCreateDeviceRGB(),
                                bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue)!
        context.draw(image, in: CGRect(x: -4, y: -4, width: 8, height: 8))
        return (pixel[0], pixel[1], pixel[2])
    }

    @Test func grayscaleEncodingDesaturatesThePhoto() {
        let jpeg = redJPEG()
        let color = centerPixel(ofBase64JPEG: Recipe.jpegBase64(from: jpeg, grayscale: false)!)
        #expect(color.r > 200 && color.g < 60 && color.b < 60, "color encoding keeps red")
        let gray = centerPixel(ofBase64JPEG: Recipe.jpegBase64(from: jpeg, grayscale: true)!)
        #expect(abs(Int(gray.r) - Int(gray.g)) < 8 && abs(Int(gray.g) - Int(gray.b)) < 8, "gray channels agree: \(gray)")
    }

    @Test func missingImageEncodesToNil() {
        #expect(Recipe.jpegBase64(from: nil, grayscale: true) == nil)
        #expect(Recipe.jpegBase64(from: Data("nope".utf8), grayscale: false) == nil)
    }
}
