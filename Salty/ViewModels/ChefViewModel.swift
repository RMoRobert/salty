//
//  ChefViewModel.swift
//  Salty
//
//  Everything Chef View needs to reason about a recipe while it's being cooked: the step rows and
//  their numbering, which step is current, what's been checked off, and finishing up. Cooking
//  progress itself is not stored here — it lives in the app-level ChefViewSessionStore, keyed by
//  recipe id, so it survives leaving and re-entering Chef View (and is shared between a macOS Chef
//  View window and the same recipe elsewhere).
//

import Foundation
import OSLog
import SQLiteData
import SaltyCore

@Observable
@MainActor
final class ChefViewModel {
    private let logger = Logger(subsystem: "Salty", category: "App")

    @ObservationIgnored
    @Dependency(\.defaultDatabase) private var database

    // MARK: - Identity and inputs

    let recipeId: String
    /// Ingredient scale carried in from the recipe detail view (1.0 = unscaled).
    let scaleFactor: Double

    /// A snapshot rather than a live `@FetchOne`: a recipe isn't edited while it's being cooked,
    /// and a plain value keeps the step logic testable without standing up a database.
    private(set) var recipe: Recipe?

    private let sessionStore: ChefViewSessionStore

    // MARK: - Transient UI state

    /// Compact width only — the ingredients live behind a drawer there (see ChefView).
    var isIngredientsDrawerShowing = false
    /// Drives the one confirmation dialog in ChefView, shared by both places that offer the action.
    var isConfirmingMarkAsMade = false
    var isMarkingAsMade = false
    var didMarkAsMade = false
    var markAsMadeErrorMessage: String?

    // MARK: - Initialization

    init(recipe: Recipe, scaleFactor: Double = 1.0, sessionStore: ChefViewSessionStore) {
        self.recipeId = recipe.id
        self.recipe = recipe
        self.scaleFactor = scaleFactor
        self.sessionStore = sessionStore
    }

    /// For the macOS Chef View window, whose Codable window value carries only an id.
    init(recipeId: String, scaleFactor: Double = 1.0, sessionStore: ChefViewSessionStore) {
        self.recipeId = recipeId
        self.recipe = nil
        self.scaleFactor = scaleFactor
        self.sessionStore = sessionStore
    }

    /// Fills in the recipe when Chef View was launched from an id alone. A no-op otherwise.
    func loadRecipeIfNeeded() async {
        guard recipe == nil else { return }
        let id = recipeId
        do {
            recipe = try await database.read { db in
                try Recipe.where { $0.id.eq(id) }.fetchOne(db)
            }
        } catch {
            logger.error("Chef View could not load recipe \(id): \(error)")
        }
    }

    // MARK: - Steps

    var recipeName: String { recipe?.name ?? "" }

    /// Direction rows as Chef View shows them, headings included. Recomputed from the snapshot;
    /// callers that iterate should bind it to a local rather than re-reading it per row.
    var steps: [ChefStep] {
        ChefStep.steps(from: recipe?.directions ?? [])
    }

    /// Just the numbered steps — headings orient the cook but are never "current" and can't be
    /// stepped onto.
    var cookableSteps: [ChefStep] {
        steps.filter { !$0.isHeading }
    }

    var totalStepCount: Int { cookableSteps.count }

    /// The step in focus. Falls back to the first cookable step so Chef View always opens on
    /// something, without having to write that choice into the session up front.
    var currentStep: ChefStep? {
        let cookable = cookableSteps
        if let id = session.currentStepId, let match = cookable.first(where: { $0.id == id }) {
            return match
        }
        return cookable.first
    }

    /// "Step 3 of 9" — nil when the recipe has no directions to count.
    var currentStepProgressLabel: String? {
        guard let number = currentStep?.number, totalStepCount > 0 else { return nil }
        return "Step \(number) of \(totalStepCount)"
    }

    /// The section heading the current step falls under, if the recipe uses them. Focus mode shows
    /// it above the step, since it never renders heading rows of its own.
    var currentSectionHeading: String? {
        guard let current = currentStep else { return nil }
        return steps.last(where: { $0.isHeading && $0.id < current.id })?.text
    }

    func isCurrent(_ step: ChefStep) -> Bool {
        !step.isHeading && step.id == currentStep?.id
    }

    func isCompleted(_ step: ChefStep) -> Bool {
        session.completedStepIds.contains(step.id)
    }

    /// Makes a step current. Headings are ignored so tapping one doesn't strand the cook on a row
    /// with no next/previous meaning.
    func select(_ step: ChefStep) {
        guard !step.isHeading else { return }
        update { $0.currentStepId = step.id }
    }

    var canGoToPreviousStep: Bool {
        guard let current = currentStep else { return false }
        return cookableSteps.first?.id != current.id
    }

    /// True while there's another step to move onto. False on the last step — where "Next" still
    /// works, completing that step and finishing the recipe.
    var canGoToNextStep: Bool {
        guard let current = currentStep else { return false }
        return cookableSteps.last?.id != current.id
    }

    /// True while "Next" still has something to do: a step to move onto, or a current step that
    /// hasn't been checked off yet. Only false once the last step is done — so the button can be
    /// disabled in place rather than swapped out for something else, and the cook is never left on
    /// a final step with no way to check it off.
    var canAdvance: Bool {
        guard let current = currentStep else { return false }
        return canGoToNextStep || !session.completedStepIds.contains(current.id)
    }

    /// Completes the current step and moves on. On the last step it completes without moving,
    /// which is what flips `isFinished` and surfaces "Made It!".
    func goToNextStep() {
        let cookable = cookableSteps
        guard let current = currentStep,
              let position = cookable.firstIndex(where: { $0.id == current.id }) else { return }
        let next = cookable.indices.contains(position + 1) ? cookable[position + 1] : nil
        update {
            $0.completedStepIds.insert(current.id)
            if let next { $0.currentStepId = next.id }
        }
    }

    /// Steps back and un-completes the step landed on — going back means redoing it, and without
    /// this, stepping back and forth would leave everything marked done.
    func goToPreviousStep() {
        let cookable = cookableSteps
        guard let current = currentStep,
              let position = cookable.firstIndex(where: { $0.id == current.id }),
              position > 0 else { return }
        let previous = cookable[position - 1]
        update {
            $0.currentStepId = previous.id
            $0.completedStepIds.remove(previous.id)
            $0.completedStepIds.remove(current.id)
        }
    }

    func toggleCompleted(_ step: ChefStep) {
        guard !step.isHeading else { return }
        update {
            if $0.completedStepIds.contains(step.id) {
                $0.completedStepIds.remove(step.id)
            } else {
                $0.completedStepIds.insert(step.id)
            }
        }
    }

    /// Every numbered step checked off. Drives the finish state (and the "Made It!" button).
    var isFinished: Bool {
        let cookable = cookableSteps
        guard !cookable.isEmpty else { return false }
        let completed = session.completedStepIds
        return cookable.allSatisfy { completed.contains($0.id) }
    }

    var completedStepCount: Int {
        let completed = session.completedStepIds
        return cookableSteps.count(where: { completed.contains($0.id) })
    }

    // MARK: - Ingredients

    var ingredients: [Ingredient] { recipe?.ingredients ?? [] }

    func isIngredientChecked(at index: Int) -> Bool {
        session.checkedIngredientIds.contains(index)
    }

    func toggleIngredientChecked(at index: Int) {
        update {
            if $0.checkedIngredientIds.contains(index) {
                $0.checkedIngredientIds.remove(index)
            } else {
                $0.checkedIngredientIds.insert(index)
            }
        }
    }

    func scaledIngredientDisplay(_ ingredient: Ingredient) -> IngredientScaler.DisplayParts {
        IngredientScaler.displayParts(for: ingredient, scaleFactor: scaleFactor)
    }

    var isScaleActive: Bool {
        abs(scaleFactor - 1.0) > 0.001
    }

    /// Display-only percent for the scale badge and footnote (e.g. `50`, `66.67`, `200`).
    var scalePercentLabel: String {
        (scaleFactor * 100).formatted(.number.precision(.fractionLength(0...2)).grouping(.never))
    }

    var scaleFootnote: String {
        "Ingredients are scaled to \(scalePercentLabel)%. Amounts and times mentioned in the directions may still refer to the original recipe — check before use."
    }

    // MARK: - Session

    var hasProgress: Bool { !session.isPristine }

    func startOver() {
        sessionStore.reset(recipeId: recipeId)
    }

    private var session: ChefSessionState {
        sessionStore.state(for: recipeId)
    }

    private func update(_ mutate: (inout ChefSessionState) -> Void) {
        sessionStore.update(recipeId: recipeId, mutate)
    }

    // MARK: - Finishing

    /// Asks for the confirmation rather than stamping the date outright. The control sits in a bar
    /// full of tap targets that get used with messy hands mid-cook, and a stray tap would otherwise
    /// silently overwrite a real Last Prepared date with today's.
    func requestMarkAsMade() {
        guard !isMarkingAsMade, !didMarkAsMade else { return }
        isConfirmingMarkAsMade = true
    }

    /// "Made It!" — stamps today onto the recipe's Last Prepared date.
    func markAsMade() async {
        guard !isMarkingAsMade else { return }
        isMarkingAsMade = true
        markAsMadeErrorMessage = nil
        do {
            try await RecipeLastPreparedWriter.setLastMade(Date(), forRecipeIds: [recipeId], in: database)
            didMarkAsMade = true
        } catch {
            logger.error("Chef View could not set the last-made date for \(self.recipeId): \(error)")
            markAsMadeErrorMessage = error.localizedDescription
        }
        isMarkingAsMade = false
    }
}
