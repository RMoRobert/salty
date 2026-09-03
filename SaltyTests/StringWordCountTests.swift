//
//  StringWordCountTests.swift
//  SaltyTests
//
//  `String.wordCount`, which replaced `NLTokenizer(unit: .word)` in RecipeFromTextParser. The
//  counter feeds a coarse "does this line look like a recipe title?" test (2...15 words), so the
//  cases that matter are the ones recipe text actually produces: fractions, possessives, stray
//  punctuation and irregular spacing.
//

import Testing
import SaltyCore

@Suite struct StringWordCountTests {

    @Test func countsWhitespaceSeparatedWords() {
        #expect("Chocolate Chip Cookies".wordCount == 3)
        #expect("Cacio e Pepe".wordCount == 3)
    }

    @Test func treatsFractionsAndMeasurementsAsSingleWords() {
        #expect("1/2 cup sugar".wordCount == 3)
        #expect("350°F".wordCount == 1)
    }

    @Test func collapsesIrregularSpacing() {
        #expect("  Grandma's   Apple  Pie  ".wordCount == 3)
        #expect("Roast\tChicken".wordCount == 2)
    }

    @Test func ignoresPunctuationOnlyTokens() {
        #expect("---".wordCount == 0)
        #expect("* * *".wordCount == 0)
        // A separator between words must not inflate the count.
        #expect("Ingredients -- for the dough".wordCount == 4)
    }

    @Test func emptyAndBlankStringsCountZero() {
        #expect("".wordCount == 0)
        #expect("   ".wordCount == 0)
    }

    @Test func titleLengthGateBehavesAsTheParserExpects() {
        // The parser skips lines under 2 or over 15 words when hunting for a title.
        #expect("Sourdough".wordCount == 1)
        #expect("Weeknight Dal".wordCount == 2)
        let longLine = Array(repeating: "word", count: 16).joined(separator: " ")
        #expect(longLine.wordCount == 16)
    }
}
