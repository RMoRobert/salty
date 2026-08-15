//
//  DirectionTextParserTests.swift
//  SaltyTests
//

import Testing
@testable import Salty
import SaltyCore

struct DirectionTextParserTests {

    @Test func splitsStepsOnBlankLine() {
        let text = "Mix dry ingredients.\n\nBake until golden."
        let directions = DirectionTextParser.parseDirections(from: text)
        #expect(directions.count == 2)
        #expect(directions[0].text == "Mix dry ingredients.")
        #expect(directions[1].text == "Bake until golden.")
        #expect(directions[0].isHeading != true)
    }

    @Test func mergesLinesUntilBreak() {
        let text = "Mix.\nStir.\n\nBake."
        let directions = DirectionTextParser.parseDirections(from: text)
        #expect(directions.count == 2)
        #expect(directions[0].text == "Mix. Stir.")
        #expect(directions[1].text == "Bake.")
    }

    @Test func parsesColonHeading() {
        let text = "Oven:\nPreheat to 350°"
        let directions = DirectionTextParser.parseDirections(from: text)
        #expect(directions.count == 2)
        #expect(directions[0].isHeading == true)
        #expect(directions[0].text == "Oven")
        #expect(directions[1].text == "Preheat to 350°")
    }

    @Test func cleanUpTextRemovesNumberedPrefix() {
        #expect(DirectionTextParser.cleanUpText("1. Mix ingredients") == "Mix ingredients")
    }
}
