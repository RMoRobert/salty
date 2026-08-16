//
//  ChefSessionState.swift
//  Salty
//
//  In-memory cooking progress for one recipe. Held by ChefViewSessionStore for the life of the
//  app session only — deliberately never written to the database, so there are no migrations, no
//  sync, and no "is this progress from three weeks ago?" staleness question.
//

import Foundation

struct ChefSessionState: Equatable {
    /// `ChefStep.id` (index into the recipe's directions) of the step being worked on.
    var currentStepId: Int?
    var completedStepIds: Set<Int> = []
    /// Indices into the recipe's `ingredients` array.
    var checkedIngredientIds: Set<Int> = []

    var isPristine: Bool {
        currentStepId == nil && completedStepIds.isEmpty && checkedIngredientIds.isEmpty
    }
}
