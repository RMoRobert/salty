//
//  ReadingOrderAssemblerTests.swift
//  SaltyTests
//
//  Column detection and line joining on synthetic layouts. Coordinates are normalised, top-left origin.
//

import Testing
import SaltyCore

struct ReadingOrderAssemblerTests {

    /// A one-line block `height` tall at (x, y).
    private func block(_ text: String, x: Double, y: Double, width: Double, height: Double = 0.03, kind: RecognizedTextBlock.Kind = .paragraph) -> RecognizedTextBlock {
        RecognizedTextBlock(kind: kind, lines: [text], x: x, y: y, width: width, height: height)
    }

    /// Two columns whose lines alternate vertically, as Vision reports them.
    private func twoColumns() -> (left: [RecognizedTextBlock], right: [RecognizedTextBlock]) {
        let left = (0..<6).map { block("L\($0)", x: 0.06, y: 0.20 + Double($0) * 0.08, width: 0.40) }
        let right = (0..<6).map { block("R\($0)", x: 0.53, y: 0.22 + Double($0) * 0.08, width: 0.40) }
        return (left, right)
    }

    @Test func twoColumnsReadColumnByColumn() {
        let (left, right) = twoColumns()
        let interleaved = zip(left, right).flatMap { [$0, $1] }
        let ordered = ReadingOrderAssembler.ordered(interleaved).map(\.transcript)
        #expect(ordered == ["L0", "L1", "L2", "L3", "L4", "L5", "R0", "R1", "R2", "R3", "R4", "R5"])
    }

    @Test func spanningTitleComesFirstThenColumns() {
        let (left, right) = twoColumns()
        let title = block("Title", x: 0.06, y: 0.05, width: 0.87, height: 0.05, kind: .title)
        let ordered = ReadingOrderAssembler.ordered(right + left + [title]).map(\.transcript)
        #expect(ordered.first == "Title")
        #expect(Array(ordered.dropFirst()) == ["L0", "L1", "L2", "L3", "L4", "L5", "R0", "R1", "R2", "R3", "R4", "R5"])
    }

    @Test func centredShortTitleStillSpans() {
        let (left, right) = twoColumns()
        let title = block("Title", x: 0.35, y: 0.05, width: 0.30, height: 0.05)
        let ordered = ReadingOrderAssembler.ordered(right + left + [title]).map(\.transcript)
        #expect(ordered.first == "Title")
        #expect(ordered.firstIndex(of: "L5")! < ordered.firstIndex(of: "R0")!)
    }

    @Test func fullWidthParagraphSplitsPageIntoBands() {
        let (left, right) = twoColumns()
        // A full-width paragraph in the middle of the page: everything above it reads first.
        let divider = block("Divider", x: 0.06, y: 0.43, width: 0.87, height: 0.04)
        let ordered = ReadingOrderAssembler.ordered(left + right + [divider]).map(\.transcript)
        // Blocks with midY < 0.43: L0 (0.215), L1 (0.295), L2 (0.375), R0 (0.235), R1 (0.315), R2 (0.395)
        #expect(ordered == ["L0", "L1", "L2", "R0", "R1", "R2", "Divider", "L3", "L4", "L5", "R3", "R4", "R5"])
    }

    @Test func singleColumnKeepsTopToBottomOrder() {
        let lines = (0..<8).map { block("P\($0)", x: 0.1, y: 0.1 + Double($0) * 0.1, width: 0.6 + Double($0 % 3) * 0.1) }
        let shuffled = [lines[3], lines[0], lines[7], lines[1], lines[5], lines[2], lines[6], lines[4]]
        #expect(ReadingOrderAssembler.ordered(shuffled).map(\.transcript) == lines.map(\.transcript))
    }

    @Test func raggedRightMarginIsNotAGutter() {
        // Short ingredient lines then wide direction paragraphs: the empty area right of the short lines
        // reaches the page edge and must not be mistaken for a column gutter.
        var blocks = (0..<6).map { block("I\($0)", x: 0.1, y: 0.1 + Double($0) * 0.05, width: 0.25) }
        blocks += (0..<4).map { block("D\($0)", x: 0.1, y: 0.45 + Double($0) * 0.1, width: 0.8, height: 0.08) }
        #expect(ReadingOrderAssembler.ordered(blocks.reversed()).map(\.transcript) == blocks.map(\.transcript))
    }

    @Test func singleBlockAndEmptyInputPassThrough() {
        #expect(ReadingOrderAssembler.ordered([]).isEmpty)
        let one = block("Only", x: 0.1, y: 0.1, width: 0.5)
        #expect(ReadingOrderAssembler.ordered([one]) == [one])
    }

    // MARK: - Table-style rows

    @Test func quantityColumnIsRejoinedWithItsIngredient() {
        // Quantities at x 0.06, names at x 0.26; Vision reports them as separate blocks in either order.
        let rows: [(String, String)] = [("2 lbs", "chicken thighs"), ("1/4 cup", "olive oil"), ("1", "lemon, juiced"), ("½ tsp", "salt")]
        var blocks: [RecognizedTextBlock] = []
        for (index, row) in rows.enumerated() {
            let y = 0.2 + Double(index) * 0.05
            blocks.append(block(row.1, x: 0.26, y: y + 0.002, width: 0.2))
            blocks.append(block(row.0, x: 0.06, y: y, width: Double(row.0.count) * 0.012))
        }
        blocks.append(block("Roast until golden and cooked through, then rest.", x: 0.06, y: 0.5, width: 0.85, height: 0.06))
        let text = ReadingOrderAssembler.assemble(blocks)
        #expect(text == "2 lbs chicken thighs\n1/4 cup olive oil\n1 lemon, juiced\n½ tsp salt\nRoast until golden and cooked through, then rest.")
    }

    @Test func shortIngredientLinesAreNotMergedAcrossAColumnGutter() {
        // Left column: short ingredient lines; right column: directions on the same baselines. The gap is
        // a real gutter, so nothing may be merged.
        var blocks: [RecognizedTextBlock] = []
        for index in 0..<4 {
            let y = 0.2 + Double(index) * 0.05
            blocks.append(block("1 tsp salt", x: 0.06, y: y, width: 0.10))
            blocks.append(block("Whisk everything together in a bowl.", x: 0.53, y: y, width: 0.40))
        }
        let ordered = ReadingOrderAssembler.ordered(blocks).map(\.transcript)
        #expect(ordered == Array(repeating: "1 tsp salt", count: 4) + Array(repeating: "Whisk everything together in a bowl.", count: 4))
    }

    @Test func detachedStepNumberIsRejoinedButNotWithAnotherItem() {
        let blocks = [
            block("1.", x: 0.06, y: 0.2, width: 0.02),
            block("Preheat the oven.", x: 0.10, y: 0.2, width: 0.3),
            block("2.", x: 0.06, y: 0.25, width: 0.02),
            block("• garnish", x: 0.10, y: 0.25, width: 0.3),
        ]
        #expect(ReadingOrderAssembler.assemble(blocks) == "1. Preheat the oven.\n2.\n• garnish")
    }

    // MARK: - Line joining

    @Test func wrappedParagraphLinesAreJoinedWithSpaces() {
        let paragraph = RecognizedTextBlock(lines: ["Whisk oil, garlic, lemon juice,", "salt and pepper in a bowl."], x: 0, y: 0, width: 1, height: 0.1)
        #expect(ReadingOrderAssembler.text(from: [paragraph]) == "Whisk oil, garlic, lemon juice, salt and pepper in a bowl.")
    }

    @Test func continuationThatStartsANewItemStaysOnItsOwnLine() {
        let merged = RecognizedTextBlock(lines: ["2 lbs chicken thighs", "3 cloves garlic, minced", "1/4 cup olive oil", "½ tsp salt", "• parsley"], x: 0, y: 0, width: 1, height: 0.1)
        #expect(ReadingOrderAssembler.text(from: [merged]) == "2 lbs chicken thighs\n3 cloves garlic, minced\n1/4 cup olive oil\n½ tsp salt\n• parsley")
    }

    @Test func numberedStepsAreSeparatedButTheirWrappedLinesJoined() {
        let steps = RecognizedTextBlock(lines: ["1. Preheat oven to 425°F.", "2. Whisk oil, garlic and", "lemon juice.", "Step 3 Roast."], x: 0, y: 0, width: 1, height: 0.1)
        #expect(ReadingOrderAssembler.text(from: [steps]) == "1. Preheat oven to 425°F.\n2. Whisk oil, garlic and lemon juice.\nStep 3 Roast.")
    }

    @Test func hyphenatedLineBreaksAreRejoined() {
        let paragraph = RecognizedTextBlock(lines: ["Marinate the chicken while the oven pre-", "heats, then com-", "bine the rest."], x: 0, y: 0, width: 1, height: 0.1)
        #expect(ReadingOrderAssembler.text(from: [paragraph]) == "Marinate the chicken while the oven preheats, then combine the rest.")
    }

    @Test func aTrailingDashBeforeACapitalIsKept() {
        let paragraph = RecognizedTextBlock(lines: ["Serves 4 -", "Great for weeknights"], x: 0, y: 0, width: 1, height: 0.1)
        #expect(ReadingOrderAssembler.text(from: [paragraph]) == "Serves 4 - Great for weeknights")
    }

    @Test func blocksBecomeSeparateLinesAndBlankLinesAreDropped() {
        let a = RecognizedTextBlock(lines: ["Title"], x: 0, y: 0, width: 1, height: 0.05)
        let empty = RecognizedTextBlock(lines: ["", "  "], x: 0, y: 0.1, width: 1, height: 0.05)
        let b = RecognizedTextBlock(lines: ["Body"], x: 0, y: 0.2, width: 1, height: 0.05)
        #expect(ReadingOrderAssembler.text(from: [a, empty, b]) == "Title\nBody")
    }
}
