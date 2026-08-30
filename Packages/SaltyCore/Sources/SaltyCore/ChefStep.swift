//
//  ChefStep.swift
//  SaltyCore
//
//  One row of a recipe's directions as Chef View shows it: the text, whether it's a section
//  heading, and — for real steps — its "Step 3 of 9" number. Pure value type so the numbering
//  rules (which is what silently regresses) can be tested without a view.
//

import Foundation

public struct ChefStep: Identifiable, Hashable, Sendable {
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

    /// Builds the Chef View rows for a recipe's directions.
    ///
    /// Headings are kept (they orient the cook) but aren't numbered, matching the
    /// prefix-count-of-non-headings convention `RecipeDetailView` uses. Blank rows — usually an
    /// artifact of adding a direction row in the editor and never typing in it — are dropped
    /// rather than rendered as an empty giant step in focus mode.
    public static func steps(from directions: [Direction]) -> [ChefStep] {
        var steps: [ChefStep] = []
        var stepNumber = 0
        for (index, direction) in directions.enumerated() {
            let text = direction.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else { continue }
            let isHeading = direction.isHeading == true
            if !isHeading { stepNumber += 1 }
            steps.append(
                ChefStep(id: index, text: text, isHeading: isHeading, number: isHeading ? nil : stepNumber)
            )
        }
        return steps
    }
}
