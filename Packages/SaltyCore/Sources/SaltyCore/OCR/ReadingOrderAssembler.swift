//
//  ReadingOrderAssembler.swift
//  SaltyCore
//
//  Puts recognised text blocks into reading order and joins them into plain text.
//
//  Vision returns blocks roughly top-to-bottom, which interleaves the columns of a multi-column
//  page. The assembler instead:
//
//  0. Re-joins table-style rows split into a quantity block ("2 lbs") and an ingredient block.
//  1. Finds gutters (vertical strips almost no text crosses) in a height-weighted horizontal
//     projection; no gutter means a single column in top-to-bottom order.
//  2. Assigns each block to its column; a block substantially in two or more columns spans them.
//  3. Reads in bands: each spanning block opens a band, whose columns are read left to right.
//
//  Wrapped lines are glued back together unless a line clearly starts a new item.
//

import Foundation

public enum ReadingOrderAssembler {

    /// Tunables, exposed so tests can probe the edges.
    public struct Options: Sendable {
        /// A vertical strip is a gutter when the text crossing it adds up to no more than this fraction
        /// of the page's text height, so a title straddling two columns doesn't hide the gutter.
        public var gutterCoverageTolerance = 0.2
        /// Minimum gutter width as a fraction of the text area's width.
        public var minimumGutterWidth = 0.015
        /// A block belongs to a column when at least this fraction of its width lies inside it; one that
        /// belongs to two or more columns spans them and separates the page into bands.
        public var columnMembership = 0.25
        /// A quantity fragment is at most this fraction of the text width wide, and its ingredient sits at
        /// most `rowGapLimit` to its right. The gap is generous because a table's ingredient column starts
        /// past its *longest* quantity.
        public var quantityWidthLimit = 0.15
        public var rowGapLimit = 0.3

        public init() {}
    }

    /// Orders blocks in reading order (see the file comment).
    public static func ordered(_ blocks: [RecognizedTextBlock], options: Options = Options()) -> [RecognizedTextBlock] {
        let topDown = blocks.sorted(by: isAbove)
        guard blocks.count > 1,
              let minX = blocks.map(\.x).min(), let maxX = blocks.map(\.maxX).max(), maxX > minX,
              let minY = blocks.map(\.y).min(), let maxY = blocks.map(\.maxY).max(), maxY > minY else {
            return topDown
        }

        let rows = mergingRowFragments(topDown, textWidth: maxX - minX, options: options)
        let columns = columnRanges(of: rows, minX: minX, maxX: maxX, textHeight: maxY - minY, options: options)
        guard columns.count > 1 else { return rows }

        var spanning: [RecognizedTextBlock] = []
        var perColumn = Array(repeating: [RecognizedTextBlock](), count: columns.count)
        for block in rows {
            let members = columns.indices.filter { overlap(of: block, with: columns[$0]) >= options.columnMembership * block.width }
            if members.count >= 2 {
                spanning.append(block)
            } else if let column = members.first {
                perColumn[column].append(block)
            } else {
                perColumn[nearestColumn(to: block.midX, in: columns)].append(block)
            }
        }

        // Band 0 holds column text above the first spanning block; every spanning block opens another.
        var bands: [(lead: [RecognizedTextBlock], columns: [[RecognizedTextBlock]])] = [([], perColumnEmpty(columns.count))]
        for block in spanning {
            bands.append(([block], perColumnEmpty(columns.count)))
        }
        for (column, list) in perColumn.enumerated() {
            for block in list {
                let band = spanning.lastIndex { $0.y <= block.midY }.map { $0 + 1 } ?? 0
                bands[band].columns[column].append(block)
            }
        }
        return bands.flatMap { $0.lead + $0.columns.flatMap { $0 } }
    }

    /// Joins ordered blocks into text: one block per line, wrapped lines glued back together.
    public static func text(from blocks: [RecognizedTextBlock]) -> String {
        blocks.compactMap { block -> String? in
            var joined = ""
            for rawLine in block.lines {
                let line = rawLine.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !line.isEmpty else { continue }
                if joined.isEmpty {
                    joined = line
                } else if startsNewItem(line) {
                    joined += "\n" + line
                } else if isHyphenated(joined, next: line) {
                    joined.removeLast()
                    joined += line
                } else {
                    joined += " " + line
                }
            }
            return joined.isEmpty ? nil : joined
        }
        .joined(separator: "\n")
    }

    /// `text(from: ordered(blocks))`.
    public static func assemble(_ blocks: [RecognizedTextBlock], options: Options = Options()) -> String {
        text(from: ordered(blocks, options: options))
    }

    // MARK: - Table-style rows

    /// Re-joins a quantity fragment with the ingredient text on the same line to its right. A partner
    /// that itself starts a new item (number, bullet) is a neighbouring column's item, not this row.
    static func mergingRowFragments(_ topDown: [RecognizedTextBlock], textWidth: Double, options: Options) -> [RecognizedTextBlock] {
        var blocks = topDown
        var index = 0
        while index < blocks.count {
            let fragment = blocks[index]
            guard isQuantityFragment(fragment, textWidth: textWidth, options: options) else {
                index += 1
                continue
            }
            let partner = blocks.indices
                .filter { $0 != index }
                .filter { candidate in
                    let block = blocks[candidate]
                    return block.x >= fragment.maxX - 0.005
                        && block.x - fragment.maxX <= options.rowGapLimit * textWidth
                        && verticalOverlap(fragment, block) >= 0.5 * min(fragment.height, block.height)
                        && !startsNewItem(block.lines.first ?? "")
                }
                .min { blocks[$0].x < blocks[$1].x }
            if let partner {
                let other = blocks[partner]
                let top = min(fragment.y, other.y)
                blocks[index] = RecognizedTextBlock(
                    kind: other.kind,
                    lines: [fragment.lines.joined(separator: " ") + " " + (other.lines.first ?? "")] + other.lines.dropFirst(),
                    x: fragment.x,
                    y: top,
                    width: other.maxX - fragment.x,
                    height: max(fragment.maxY, other.maxY) - top
                )
                blocks.remove(at: partner)
                if partner < index { index -= 1 }
            }
            index += 1
        }
        return blocks
    }

    /// A one-line block that is nothing but a quantity: a number or fraction ("2", "1/4", "½", "1.")
    /// optionally followed by up to two unit words ("lbs", "fl oz", "large cloves"), narrow enough to be
    /// a table's first column. "1 tsp salt" names an ingredient and is not a fragment.
    static func isQuantityFragment(_ block: RecognizedTextBlock, textWidth: Double, options: Options) -> Bool {
        guard block.lines.count == 1, let line = block.lines.first,
              block.width <= options.quantityWidthLimit * textWidth else { return false }
        let words = line.split(whereSeparator: \.isWhitespace).map { $0.lowercased().trimmingCharacters(in: .punctuationCharacters) }
        guard (1...3).contains(words.count), let first = words.first?.first else { return false }
        guard first.isNumber || "½⅓⅔¼¾⅛⅜⅝⅞".contains(first) else { return false }
        return words.dropFirst().allSatisfy { unitWords.contains($0) || $0.isEmpty }
    }

    /// Units and portion words that can follow a quantity in a table's first column.
    private static let unitWords: Set<String> = [
        "c", "cup", "cups", "tsp", "tsps", "teaspoon", "teaspoons", "tbsp", "tbsps", "tbl", "tablespoon", "tablespoons",
        "oz", "ounce", "ounces", "fl", "lb", "lbs", "pound", "pounds", "g", "gr", "gram", "grams", "kg", "kilogram", "kilograms",
        "ml", "l", "liter", "liters", "litre", "litres", "qt", "quart", "quarts", "pt", "pint", "pints", "gal", "gallon", "gallons",
        "clove", "cloves", "can", "cans", "pkg", "package", "packages", "stick", "sticks", "pinch", "dash", "slice", "slices",
        "sprig", "sprigs", "bunch", "bunches", "head", "heads", "stalk", "stalks", "piece", "pieces", "large", "medium", "small",
        "whole", "handful", "each", "x",
    ]

    private static func verticalOverlap(_ a: RecognizedTextBlock, _ b: RecognizedTextBlock) -> Double {
        max(0, min(a.maxY, b.maxY) - max(a.y, b.y))
    }

    // MARK: - Columns

    /// The horizontal ranges of the page's columns, found by looking for gutters in a height-weighted
    /// projection of the blocks. Whitespace touching either edge is margin, not a gutter.
    static func columnRanges(
        of blocks: [RecognizedTextBlock], minX: Double, maxX: Double, textHeight: Double, options: Options
    ) -> [ClosedRange<Double>] {
        let bins = 500
        let width = maxX - minX
        var coverage = [Double](repeating: 0, count: bins)
        for block in blocks {
            let low = min(max(Int(((block.x - minX) / width * Double(bins)).rounded(.down)), 0), bins - 1)
            let high = min(max(Int(((block.maxX - minX) / width * Double(bins)).rounded(.up)) - 1, low), bins - 1)
            for bin in low...high {
                coverage[bin] += block.height
            }
        }

        let tolerance = options.gutterCoverageTolerance * textHeight
        let minimumBins = max(1, Int((options.minimumGutterWidth * Double(bins)).rounded()))
        var gutters: [Range<Int>] = []
        var runStart: Int?
        for bin in 0..<bins {
            if coverage[bin] <= tolerance {
                runStart = runStart ?? bin
            } else if let start = runStart {
                if start > 0 && bin - start >= minimumBins {
                    gutters.append(start..<bin)
                }
                runStart = nil
            }
        }

        let xAt = { (bin: Int) in minX + Double(bin) / Double(bins) * width }
        var ranges: [ClosedRange<Double>] = []
        var start = 0
        for gutter in gutters {
            ranges.append(xAt(start)...xAt(gutter.lowerBound))
            start = gutter.upperBound
        }
        ranges.append(xAt(start)...maxX)
        return ranges
    }

    private static func overlap(of block: RecognizedTextBlock, with column: ClosedRange<Double>) -> Double {
        max(0, min(block.maxX, column.upperBound) - max(block.x, column.lowerBound))
    }

    private static func nearestColumn(to x: Double, in columns: [ClosedRange<Double>]) -> Int {
        columns.indices.min { distance(from: x, to: columns[$0]) < distance(from: x, to: columns[$1]) } ?? 0
    }

    private static func distance(from x: Double, to range: ClosedRange<Double>) -> Double {
        range.contains(x) ? 0 : min(abs(x - range.lowerBound), abs(x - range.upperBound))
    }

    private static func perColumnEmpty(_ count: Int) -> [[RecognizedTextBlock]] {
        Array(repeating: [], count: count)
    }

    private static func isAbove(_ a: RecognizedTextBlock, _ b: RecognizedTextBlock) -> Bool {
        a.y != b.y ? a.y < b.y : a.x < b.x
    }

    // MARK: - Line joining

    /// A continuation line that is really the start of a new ingredient or step: a bullet, a step
    /// number, or a quantity (digits, a fraction, a fraction glyph) followed by more text.
    static func startsNewItem(_ line: String) -> Bool {
        line.firstMatch(of: newItemPattern) != nil
    }

    /// Computed rather than stored: `Regex` isn't Sendable, so a stored static would be a shared mutable global.
    private static var newItemPattern: Regex<Substring> {
        /^(?:[•·▪▫‣⁃*\-–—]\s|\d+[.)]\s|[Ss]tep\s*\d|\d+\s*[\/⁄]\s*\d+\s|[½⅓⅔¼¾⅛⅜⅝⅞]\s|\d+(?:\.\d+)?\s+\S)/
    }

    /// "com-" + "bine" -> "combine": a hyphen ending the text so far, preceded by a letter, followed by a
    /// lowercase continuation.
    private static func isHyphenated(_ text: String, next: String) -> Bool {
        guard text.hasSuffix("-"), let beforeHyphen = text.dropLast().last, beforeHyphen.isLetter,
              let first = next.first else { return false }
        return first.isLowercase
    }
}
