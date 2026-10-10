//
//  DirectionStep.swift
//  SaltyCore
//
//  One row of a recipe's directions with its step number: the text, whether it's a section heading,
//  and — for real steps — its "Step 3 of 9" number. Every view of a recipe numbers steps through
//  `steps(from:includingBlankRows:)`: Chef View, the detail view, the printout and the plain-text
//  export drop blank rows, and the editor keeps them (it shows them, so they need a number). Pure
//  value type so the numbering rules, which are what silently regress, can be tested without a view.
//

import Foundation

public struct DirectionStep: Identifiable, Hashable, Sendable {
    /// Index of this row in the recipe's `directions` array. Used as the identity because
    /// `Direction.id` comes from imported files and isn't guaranteed unique within a recipe.
    public let id: Int
    public let text: String
    public let isHeading: Bool
    /// 1-based cook step number, counting only non-heading rows. Nil for headings.
    public let number: Int?

    public init(id: Int, text: String, isHeading: Bool, number: Int?) {
        self.id = id
        self.text = text
        self.isHeading = isHeading
        self.number = number
    }

    /// Builds the numbered rows of a recipe's directions.
    ///
    /// Headings are kept (they orient the cook) but aren't numbered. Blank rows — usually an
    /// artifact of adding a direction row in the editor and never typing in it — are dropped and
    /// don't take a number, rather than showing as an empty step (a giant one in Chef View's focus
    /// mode).
    ///
    /// - Parameter includingBlankRows: Keep blank rows and number them like any other step. For the
    ///   editor, which shows every row; with it, the result has one row per direction, in order.
    public static func steps(from directions: [Direction], includingBlankRows: Bool = false) -> [DirectionStep] {
        var steps: [DirectionStep] = []
        var stepNumber = 0
        for (index, direction) in directions.enumerated() {
            let text = direction.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard includingBlankRows || !text.isEmpty else { continue }
            let isHeading = direction.isHeading == true
            if !isHeading { stepNumber += 1 }
            steps.append(
                DirectionStep(id: index, text: text, isHeading: isHeading, number: isHeading ? nil : stepNumber)
            )
        }
        return steps
    }
}
