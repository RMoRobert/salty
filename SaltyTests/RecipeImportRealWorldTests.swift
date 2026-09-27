//
//  RecipeImportRealWorldTests.swift
//  SaltyTests
//
//  End-to-end runs of the real recognisers (Vision OCR via RecipeOCRService, and Smart Parse where
//  available) on rendered recipe pages. Results are printed to the test log; assertions stay loose
//  because both engines vary across OS versions, and the model across runs.
//

import Testing
import Foundation
import CoreGraphics
import CoreText
import SaltyCore
@testable import Salty

@MainActor
struct RecipeImportRealWorldTests {

    // MARK: - Page rendering

    private struct Page {
        let width = 1600
        let height = 1200
        let context: CGContext

        init() {
            context = CGContext(
                data: nil, width: width, height: height, bitsPerComponent: 8, bytesPerRow: 0,
                space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: CGImageAlphaInfo.noneSkipLast.rawValue
            )!
            context.setFillColor(CGColor(red: 1, green: 1, blue: 1, alpha: 1))
            context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        }

        /// Draws one line with its baseline `fromTop` pixels below the top edge.
        func text(_ string: String, x: CGFloat, fromTop: CGFloat, size: CGFloat, bold: Bool = false) {
            let font = CTFontCreateWithName((bold ? "Helvetica-Bold" : "Helvetica") as CFString, size, nil)
            let attributed = NSAttributedString(string: string, attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0, alpha: 1),
            ])
            context.textPosition = CGPoint(x: x, y: CGFloat(height) - fromTop)
            CTLineDraw(CTLineCreateWithAttributedString(attributed), context)
        }

        func lines(_ strings: [String], x: CGFloat, fromTop: CGFloat, leading: CGFloat = 46, size: CGFloat = 26) {
            for (index, string) in strings.enumerated() where !string.isEmpty {
                text(string, x: x, fromTop: fromTop + CGFloat(index) * leading, size: size)
            }
        }

        var image: CGImage { context.makeImage()! }
    }

    private let ingredients = [
        "2 lbs chicken thighs", "3 cloves garlic, minced", "1/4 cup olive oil", "1 lemon, juiced",
        "1 tsp salt", "1/2 tsp black pepper", "2 tbsp fresh parsley",
    ]

    /// Narrow gutter, offset baselines, no section headers: the layout line-based OCR interleaves.
    private func hardTwoColumnPage() -> CGImage {
        let page = Page()
        page.text("Lemon Garlic Chicken", x: 100, fromTop: 100, size: 44, bold: true)
        page.lines(["This bright weeknight roast comes", "together in one pan. Marinate the", "chicken while the oven heats.", ""] + ingredients,
                   x: 100, fromTop: 200)
        page.lines(["Preheat oven to 425°F. Whisk oil,", "garlic, lemon juice, salt and pepper", "in a bowl until combined.", "",
                    "Toss chicken in the marinade and", "let stand 10 minutes.", "",
                    "Roast 35 minutes until golden and", "cooked through. Garnish with", "parsley and serve warm."],
                   x: 780, fromTop: 178)
        return page.image
    }

    /// Magazine style: full-width title and introduction, two columns below, a page number at the foot.
    private func magazinePage() -> CGImage {
        let page = Page()
        page.text("Lemon Garlic Chicken", x: 100, fromTop: 100, size: 48, bold: true)
        page.text("A bright, one-pan weeknight roast that leaves you time to make a salad while it cooks.", x: 100, fromTop: 170, size: 24)
        page.text("Ingredients", x: 100, fromTop: 260, size: 32, bold: true)
        page.lines(ingredients.map { "• " + $0 }, x: 100, fromTop: 320)
        page.text("Method", x: 820, fromTop: 260, size: 32, bold: true)
        page.lines(["1. Preheat oven to 425°F.", "2. Whisk oil, garlic, lemon juice,", "    salt and pepper in a bowl.",
                    "3. Toss chicken in the marinade.", "4. Roast 35 minutes until golden.", "5. Garnish with parsley and serve."],
                   x: 820, fromTop: 320)
        page.text("42", x: 780, fromTop: 1150, size: 22)
        return page.image
    }

    /// Single column with a tabular ingredient list (quantity gap) and paragraphs of directions.
    private func tabularSingleColumnPage() -> CGImage {
        let page = Page()
        page.text("Lemon Garlic Chicken", x: 100, fromTop: 100, size: 44, bold: true)
        page.text("Serves 4", x: 100, fromTop: 150, size: 24)
        let rows: [(String, String)] = [("2 lbs", "chicken thighs"), ("3 cloves", "garlic, minced"), ("1/4 cup", "olive oil"),
                                        ("1", "lemon, juiced"), ("1 tsp", "salt"), ("1/2 tsp", "black pepper"), ("2 tbsp", "fresh parsley")]
        for (index, row) in rows.enumerated() {
            page.text(row.0, x: 100, fromTop: 230 + CGFloat(index) * 44, size: 26)
            page.text(row.1, x: 420, fromTop: 230 + CGFloat(index) * 44, size: 26)
        }
        page.lines(["Preheat oven to 425°F. Whisk oil, garlic, lemon juice, salt and pepper in a bowl until",
                    "combined. Toss chicken in the marinade and let stand 10 minutes.",
                    "",
                    "Roast 35 minutes until golden and cooked through. Garnish with parsley and serve warm."],
                   x: 100, fromTop: 600)
        return page.image
    }

    /// A phone-photo stand-in for a cookbook spread: cream page, serif type, slight rotation, two
    /// columns without section headers, a caption under a "photo" box.
    private func photoLikePage() -> CGImage {
        let page = Page()
        page.context.setFillColor(CGColor(red: 0.96, green: 0.94, blue: 0.88, alpha: 1))
        page.context.fill(CGRect(x: 0, y: 0, width: page.width, height: page.height))
        page.context.saveGState()
        page.context.translateBy(x: CGFloat(page.width) / 2, y: CGFloat(page.height) / 2)
        page.context.rotate(by: 2 * .pi / 180)
        page.context.translateBy(x: -CGFloat(page.width) / 2, y: -CGFloat(page.height) / 2)
        func serif(_ string: String, x: CGFloat, fromTop: CGFloat, size: CGFloat, bold: Bool = false) {
            let font = CTFontCreateWithName((bold ? "Georgia-Bold" : "Georgia") as CFString, size, nil)
            let attributed = NSAttributedString(string: string, attributes: [
                NSAttributedString.Key(kCTFontAttributeName as String): font,
                NSAttributedString.Key(kCTForegroundColorAttributeName as String): CGColor(gray: 0.15, alpha: 1),
            ])
            page.context.textPosition = CGPoint(x: x, y: CGFloat(page.height) - fromTop)
            CTLineDraw(CTLineCreateWithAttributedString(attributed), page.context)
        }
        serif("Lemon Garlic Chicken", x: 120, fromTop: 120, size: 46, bold: true)
        // A grey "photo" with a caption, top right.
        page.context.setFillColor(CGColor(gray: 0.6, alpha: 1))
        page.context.fill(CGRect(x: 900, y: CGFloat(page.height) - 330, width: 560, height: 230))
        serif("Roasted thighs, ready to serve", x: 900, fromTop: 360, size: 20)
        let left = ["This bright weeknight roast comes", "together in one pan. Marinate the", "chicken while the oven heats.", ""] + ingredients
        for (index, line) in left.enumerated() where !line.isEmpty {
            serif(line, x: 120, fromTop: 220 + CGFloat(index) * 46, size: 26)
        }
        let right = ["Preheat oven to 425°F. Whisk oil,", "garlic, lemon juice, salt and pepper", "in a bowl until combined.", "",
                     "Toss chicken in the marinade and", "let stand 10 minutes.", "",
                     "Roast 35 minutes until golden and", "cooked through. Garnish with", "parsley and serve warm."]
        for (index, line) in right.enumerated() where !line.isEmpty {
            serif(line, x: 860, fromTop: 430 + CGFloat(index) * 46, size: 26)
        }
        page.context.restoreGState()
        return page.image
    }

    // MARK: - OCR

    private func ocr(_ image: CGImage, label: String) async throws -> String {
        let service = RecipeOCRService()
        await service.extractText(from: image)
        try #require(service.error == nil, "OCR failed for \(label): \(String(describing: service.error))")
        print("===== OCR: \(label) =====\n\(service.extractedText)\n===== end =====")
        return service.extractedText
    }

    /// Index of the line containing `needle`, or nil.
    private func line(of needle: String, in text: String) -> Int? {
        text.components(separatedBy: .newlines).firstIndex { $0.localizedStandardContains(needle) }
    }

    @Test func hardTwoColumnPageReadsColumnByColumn() async throws {
        let text = try await ocr(hardTwoColumnPage(), label: "hard two-column")
        let lastIngredient = try #require(line(of: "fresh parsley", in: text))
        let firstDirection = try #require(line(of: "Preheat oven", in: text))
        let intro = try #require(line(of: "weeknight roast", in: text))
        #expect(intro < lastIngredient, "introduction should precede the ingredients")
        #expect(lastIngredient < firstDirection, "the whole left column should precede the right column")
        #expect(text.localizedStandardContains("2 lbs chicken"), "unit misread should be cleaned up")
    }

    @Test func magazinePageKeepsTitleIntroAndColumnsInOrder() async throws {
        let text = try await ocr(magazinePage(), label: "magazine")
        let title = try #require(line(of: "Lemon Garlic Chicken", in: text))
        let intro = try #require(line(of: "one-pan weeknight", in: text))
        let lastIngredient = try #require(line(of: "fresh parsley", in: text))
        let firstStep = try #require(line(of: "Preheat oven", in: text))
        let wrappedStep = try #require(line(of: "Whisk oil", in: text))
        #expect(title < intro && intro < lastIngredient && lastIngredient < firstStep)
        #expect(text.components(separatedBy: .newlines)[wrappedStep].localizedStandardContains("in a bowl"),
                "a wrapped numbered step should be rejoined onto one line")
    }

    @Test func tabularSingleColumnPageKeepsRowsTogether() async throws {
        let text = try await ocr(tabularSingleColumnPage(), label: "tabular single column")
        for row in ["chicken thighs", "garlic, minced", "olive oil", "black pepper"] {
            let index = try #require(line(of: row, in: text), "missing \(row)")
            let lineText = text.components(separatedBy: .newlines)[index]
            #expect(lineText.first?.isNumber == true, "quantity and ingredient should stay on one line: '\(lineText)'")
        }
        let lastIngredient = try #require(line(of: "fresh parsley", in: text))
        let firstDirection = try #require(line(of: "Preheat oven", in: text))
        #expect(lastIngredient < firstDirection)
    }

    @Test func photoLikeSpreadReadsColumnByColumn() async throws {
        let text = try await ocr(photoLikePage(), label: "photo-like spread")
        let lastIngredient = try #require(line(of: "fresh parsley", in: text))
        let firstDirection = try #require(line(of: "Preheat oven", in: text))
        let lastDirection = try #require(line(of: "serve warm", in: text))
        #expect(lastIngredient < firstDirection, "left column before right column")
        #expect(firstDirection < lastDirection)
        #expect(text.localizedStandardContains("2 lbs chicken"))
    }

    // MARK: - Smart Parse

    @Test func smartParseStructuresInterleavedText() async throws {
        guard RecipeImportParser.isSmartParseAvailable else {
            print("Smart Parse unavailable on this host; skipping")
            return
        }
        // The hard page as line-based OCR interleaves it.
        let text = """
            Lemon Garlic Chicken
            This bright weeknight roast comes
            together in one pan. Marinate the
            chicken while the oven heats.
            Preheat oven to 425°F. Whisk oil,
            garlic, lemon juice, salt and pepper
            in a bowl until combined.
            2 lbs chicken thighs
            3 cloves garlic, minced
            1/4 cup olive oil
            1 lemon, juiced
            1 tsp salt
            1/2 tsp black pepper
            2 tbsp fresh parsley
            Toss chicken in the marinade and
            let stand 10 minutes.
            Roast 35 minutes until golden and
            cooked through. Garnish with
            parsley and serve warm.
            """
        let started = Date()
        let result = await RecipeImportParser.parse(text, preferSmart: true)
        let recipe = result.recipe
        print("===== Smart Parse (\(result.method), \(Date().timeIntervalSince(started).formatted(.number.precision(.fractionLength(1))))s) =====")
        print("name: \(recipe.name)\nintro: \(recipe.introduction)\nyield: \(recipe.yield) servings: \(String(describing: recipe.servings))")
        recipe.ingredients.forEach { print("  - \($0.isHeading ? "[heading] " : "")\($0.text)") }
        recipe.directions.forEach { print("  * \($0.isHeading == true ? "[heading] " : "")\($0.text)") }
        recipe.notes.forEach { print("  note: \($0.content)") }
        print("===== end =====")

        #expect(result.method == .smart)
        #expect(recipe.name.localizedStandardContains("Lemon Garlic Chicken"))
        #expect(recipe.ingredients.count == 7)
        #expect((3...6).contains(recipe.directions.count))
        #expect(recipe.yield.isEmpty && recipe.servings == nil, "no yield in the text, so none should be invented")
    }

    @Test func smartParseOnScannedMagazinePage() async throws {
        guard RecipeImportParser.isSmartParseAvailable else { return }
        let text = try await ocr(magazinePage(), label: "magazine (for smart parse)")
        let result = await RecipeImportParser.parse(text, preferSmart: true)
        let recipe = result.recipe
        print("===== Smart Parse on magazine OCR (\(result.method)) =====")
        print("name: \(recipe.name)\nintro: \(recipe.introduction)")
        recipe.ingredients.forEach { print("  - \($0.text)") }
        recipe.directions.forEach { print("  * \($0.text)") }
        print("===== end =====")
        #expect(result.method == .smart)
        #expect(recipe.ingredients.count == 7)
        #expect(recipe.directions.count == 5)
        #expect(!recipe.directions.contains { $0.text == "42" || $0.text.hasSuffix(" 42") }, "page number should be ignored")
    }
}
