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
    /// `DirectionStep.id` (index into the recipe's directions) of the step being worked on.
    var currentStepId: Int?
    var completedStepIds: Set<Int> = []
    /// Indices into the recipe's `ingredients` array.
    var checkedIngredientIds: Set<Int> = []
    /// The recipe's `lastModifiedDate` when this progress was made. Everything above is a position
    /// in the recipe's arrays, so once the recipe has been edited it points at the wrong rows;
    /// `ChefViewModel` drops progress whose stamp no longer matches.
    var recipeLastModifiedDate: Date?

    /// No progress worth keeping. The stamp alone is nothing to keep.
    var isPristine: Bool {
        currentStepId == nil && completedStepIds.isEmpty && checkedIngredientIds.isEmpty
    }
}
