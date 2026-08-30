//
//  ChefStepTests.swift
//  SaltyTests
//
//  Chef View's step numbering. Headings interleaved with steps are exactly the kind of thing that
//  regresses silently — the count is right until someone adds a heading in the middle.
//

import Testing
@testable import Salty
import SaltyCore

struct ChefStepTests {

    private func direction(_ text: String, heading: Bool = false) -> Direction {
        Direction(id: "d-\(text)", isHeading: heading ? true : nil, text: text)
    }

    @Test func numbersOnlyNonHeadingRows() {
        let steps = ChefStep.steps(from: [
            direction("For the Dough", heading: true),
            direction("Mix the flour and water."),
            direction("Knead for ten minutes."),
            direction("For the Sauce", heading: true),
            direction("Simmer the tomatoes."),
        ])

        #expect(steps.map(\.number) == [nil, 1, 2, nil, 3])
        #expect(steps.map(\.isHeading) == [true, false, false, true, false])
    }

    @Test func identifiesStepsByPositionInTheDirectionsArray() {
        // Direction.id comes from imported files and isn't guaranteed unique, so identity is the
        // index — including across the headings, which keeps ids lining up with `recipe.directions`.
        let steps = ChefStep.steps(from: [
            direction("Prep", heading: true),
            direction("Chop the onion."),
            direction("Fry the onion."),
        ])

        #expect(steps.map(\.id) == [0, 1, 2])
    }

    @Test func dropsBlankRowsAndKeepsNumberingContiguous() {
        // A direction row added in the editor and never typed into shouldn't become an empty giant
        // step in focus mode — nor take a number with it.
        let steps = ChefStep.steps(from: [
            direction("Chop the onion."),
            direction("   "),
            direction(""),
            direction("Fry the onion."),
        ])

        #expect(steps.map(\.number) == [1, 2])
        #expect(steps.map(\.id) == [0, 3])
    }

    @Test func trimsSurroundingWhitespaceFromStepText() {
        let steps = ChefStep.steps(from: [direction("  Rest the dough.\n")])
        #expect(steps.map(\.text) == ["Rest the dough."])
    }

    @Test func handlesRecipesWithNoDirections() {
        #expect(ChefStep.steps(from: []).isEmpty)
    }

    @Test func handlesDirectionsThatAreAllHeadings() {
        let steps = ChefStep.steps(from: [direction("Day One", heading: true)])
        #expect(steps.count == 1)
        #expect(steps[0].number == nil)
    }
}
