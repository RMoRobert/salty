//
//  ChefViewModelTests.swift
//  SaltyTests
//
//  Chef View's step navigation and check-off. These exercise the view model against an in-memory
//  session store only — no database is touched, so nothing here needs the `.serialized`
//  dependency-context treatment the database tests require.
//

import Testing
import Foundation
@testable import Salty
import SaltyCore

@MainActor
struct ChefViewModelTests {

    // MARK: - Fixtures

    /// Two headings interleaved with four steps: heading, 1, 2, heading, 3, 4.
    private func makeRecipe() -> Recipe {
        Recipe(
            id: "recipe-1",
            name: "Test Loaf",
            directions: [
                Direction(id: "d0", isHeading: true, text: "For the Dough"),
                Direction(id: "d1", text: "Mix the flour and water."),
                Direction(id: "d2", text: "Knead for ten minutes."),
                Direction(id: "d3", isHeading: true, text: "To Bake"),
                Direction(id: "d4", text: "Shape the loaf."),
                Direction(id: "d5", text: "Bake for forty minutes."),
            ],
            ingredients: [
                Ingredient(id: "i0", isHeading: true, text: "Dough"),
                Ingredient(id: "i1", text: "500 g flour"),
                Ingredient(id: "i2", text: "350 g water"),
            ]
        )
    }

    private func makeViewModel(
        recipe: Recipe? = nil,
        scaleFactor: Double = 1.0,
        store: ChefViewSessionStore = ChefViewSessionStore()
    ) -> ChefViewModel {
        ChefViewModel(recipe: recipe ?? makeRecipe(), scaleFactor: scaleFactor, sessionStore: store)
    }

    // MARK: - Steps and numbering

    @Test func cookableStepsExcludeHeadings() {
        let viewModel = makeViewModel()
        #expect(viewModel.steps.count == 6)
        #expect(viewModel.totalStepCount == 4)
        #expect(viewModel.cookableSteps.map(\.number) == [1, 2, 3, 4])
    }

    @Test func opensOnTheFirstStepWithoutWritingToTheSession() {
        let store = ChefViewSessionStore()
        let viewModel = makeViewModel(store: store)

        #expect(viewModel.currentStep?.number == 1)
        #expect(viewModel.currentStepProgressLabel == "Step 1 of 4")
        // Merely opening Chef View isn't progress — "Start Over" should stay disabled.
        #expect(!viewModel.hasProgress)
    }

    // MARK: - Navigation

    @Test func nextSkipsHeadingsAndCompletesTheStepItLeaves() {
        let viewModel = makeViewModel()
        let first = viewModel.cookableSteps[0]

        viewModel.goToNextStep()

        #expect(viewModel.currentStep?.number == 2)
        #expect(viewModel.isCompleted(first))
    }

    @Test func nextWalksPastAnInteriorHeading() {
        let viewModel = makeViewModel()
        viewModel.goToNextStep()   // → step 2
        viewModel.goToNextStep()   // → step 3, stepping over the "To Bake" heading

        #expect(viewModel.currentStep?.number == 3)
        #expect(viewModel.currentStep?.text == "Shape the loaf.")
    }

    @Test func nextOnTheLastStepCompletesWithoutMoving() {
        let viewModel = makeViewModel()
        for _ in 0..<3 { viewModel.goToNextStep() }
        #expect(viewModel.currentStep?.number == 4)

        viewModel.goToNextStep()

        #expect(viewModel.currentStep?.number == 4)
        #expect(viewModel.isFinished)
    }

    @Test func previousUncompletesTheStepItLandsOn() {
        let viewModel = makeViewModel()
        viewModel.goToNextStep()   // completes step 1, now on 2

        viewModel.goToPreviousStep()

        #expect(viewModel.currentStep?.number == 1)
        // Going back means redoing it — otherwise stepping back and forth leaves everything done.
        #expect(!viewModel.isCompleted(viewModel.cookableSteps[0]))
    }

    @Test func navigationStopsAtTheEnds() {
        let viewModel = makeViewModel()
        #expect(!viewModel.canGoToPreviousStep)
        #expect(viewModel.canGoToNextStep)

        viewModel.goToPreviousStep()
        #expect(viewModel.currentStep?.number == 1)

        for _ in 0..<3 { viewModel.goToNextStep() }
        #expect(!viewModel.canGoToNextStep)
        #expect(viewModel.canGoToPreviousStep)
    }

    /// "Next" stays put and disables in place rather than being swapped out, so it has to remain
    /// usable on the last step — otherwise the final step could never be checked off in focus mode,
    /// which has no checkmarks of its own.
    @Test func nextStaysAvailableUntilTheLastStepIsCheckedOff() {
        let viewModel = makeViewModel()

        for _ in 0..<3 {
            #expect(viewModel.canAdvance)
            viewModel.goToNextStep()
        }

        // On the last step, not yet completed: Next still has work to do.
        #expect(!viewModel.canGoToNextStep)
        #expect(viewModel.canAdvance)

        viewModel.goToNextStep()

        #expect(viewModel.isFinished)
        #expect(!viewModel.canAdvance)
    }

    @Test func unCheckingTheLastStepMakesNextUsableAgain() {
        let viewModel = makeViewModel()
        for _ in 0..<4 { viewModel.goToNextStep() }
        #expect(!viewModel.canAdvance)

        viewModel.toggleCompleted(viewModel.cookableSteps[3])

        #expect(viewModel.canAdvance)
    }

    @Test func aRecipeWithNoStepsCannotAdvance() {
        #expect(!makeViewModel(recipe: Recipe(id: "empty", name: "Empty")).canAdvance)
    }

    @Test func selectingAHeadingIsIgnored() {
        let viewModel = makeViewModel()
        let heading = viewModel.steps[0]
        #expect(heading.isHeading)

        viewModel.select(heading)

        #expect(viewModel.currentStep?.number == 1)
    }

    @Test func selectingAStepMakesItCurrentWithoutCompletingAnything() {
        let viewModel = makeViewModel()
        let third = viewModel.cookableSteps[2]

        viewModel.select(third)

        #expect(viewModel.currentStep?.id == third.id)
        #expect(viewModel.completedStepCount == 0)
    }

    // MARK: - Check-off and completion

    @Test func togglingCompletionCountsTowardsFinishing() {
        let viewModel = makeViewModel()
        for step in viewModel.cookableSteps {
            #expect(!viewModel.isFinished)
            viewModel.toggleCompleted(step)
        }

        #expect(viewModel.completedStepCount == 4)
        #expect(viewModel.isFinished)

        viewModel.toggleCompleted(viewModel.cookableSteps[1])
        #expect(!viewModel.isFinished)
    }

    @Test func aRecipeWithNoStepsIsNeverFinished() {
        let viewModel = makeViewModel(recipe: Recipe(id: "empty", name: "Empty"))
        #expect(viewModel.totalStepCount == 0)
        #expect(!viewModel.isFinished)
        #expect(viewModel.currentStep == nil)
        #expect(viewModel.currentStepProgressLabel == nil)
    }

    @Test func ingredientsCheckOffIndependently() {
        let viewModel = makeViewModel()

        viewModel.toggleIngredientChecked(at: 1)

        #expect(viewModel.isIngredientChecked(at: 1))
        #expect(!viewModel.isIngredientChecked(at: 2))

        viewModel.toggleIngredientChecked(at: 1)
        #expect(!viewModel.isIngredientChecked(at: 1))
    }

    // MARK: - Section headings

    @Test func reportsTheHeadingTheCurrentStepFallsUnder() {
        let viewModel = makeViewModel()
        #expect(viewModel.currentSectionHeading == "For the Dough")

        viewModel.select(viewModel.cookableSteps[2])
        #expect(viewModel.currentSectionHeading == "To Bake")
    }

    // MARK: - Session store

    @Test func progressSurvivesLeavingAndReenteringChefView() {
        let store = ChefViewSessionStore()
        let recipe = makeRecipe()

        let first = ChefViewModel(recipe: recipe, sessionStore: store)
        first.goToNextStep()
        first.toggleIngredientChecked(at: 1)

        // Leaving Chef View and coming back builds a fresh view model over the same store.
        let second = ChefViewModel(recipe: recipe, sessionStore: store)

        #expect(second.currentStep?.number == 2)
        #expect(second.isCompleted(second.cookableSteps[0]))
        #expect(second.isIngredientChecked(at: 1))
        #expect(second.hasProgress)
    }

    @Test func progressIsKeptPerRecipe() {
        let store = ChefViewSessionStore()
        let loaf = makeViewModel(store: store)
        var other = makeRecipe()
        other.id = "recipe-2"

        loaf.goToNextStep()
        let otherViewModel = ChefViewModel(recipe: other, sessionStore: store)

        #expect(otherViewModel.currentStep?.number == 1)
        #expect(!otherViewModel.hasProgress)
        #expect(store.hasProgress(for: "recipe-1"))
    }

    @Test func startOverClearsEverything() {
        let viewModel = makeViewModel()
        viewModel.goToNextStep()
        viewModel.toggleIngredientChecked(at: 1)
        #expect(viewModel.hasProgress)

        viewModel.startOver()

        #expect(!viewModel.hasProgress)
        #expect(viewModel.currentStep?.number == 1)
        #expect(viewModel.completedStepCount == 0)
        #expect(!viewModel.isIngredientChecked(at: 1))
    }

    // MARK: - Scaling passthrough

    @Test func scaledIngredientsUseTheScaleCarriedInFromTheDetailView() {
        let viewModel = makeViewModel(scaleFactor: 0.5)
        #expect(viewModel.isScaleActive)
        #expect(viewModel.scalePercentLabel == "50")

        let parts = viewModel.scaledIngredientDisplay(Ingredient(id: "i", text: "500 g flour"))
        #expect(parts.quantity == "250 g")
        #expect(parts.remainder == "flour")
    }

    @Test func anUnscaledRecipeShowsNoScaleBadge() {
        #expect(!makeViewModel().isScaleActive)
    }

    // MARK: - Mark as prepared

    /// The bar link and the More menu both ask before writing; neither stamps the date on its own.
    @Test func requestingMarkAsPreparedOnlyOpensTheConfirmation() {
        let viewModel = makeViewModel()
        #expect(!viewModel.isConfirmingMarkAsMade)

        viewModel.requestMarkAsMade()

        #expect(viewModel.isConfirmingMarkAsMade)
        #expect(!viewModel.didMarkAsMade)
        #expect(!viewModel.isMarkingAsMade)
    }

    @Test func requestingMarkAsPreparedDoesNothingOnceAlreadyPrepared() {
        let viewModel = makeViewModel()
        viewModel.didMarkAsMade = true

        viewModel.requestMarkAsMade()

        #expect(!viewModel.isConfirmingMarkAsMade)
    }

    @Test func requestingMarkAsPreparedDoesNothingWhileAWriteIsInFlight() {
        let viewModel = makeViewModel()
        viewModel.isMarkingAsMade = true

        viewModel.requestMarkAsMade()

        #expect(!viewModel.isConfirmingMarkAsMade)
    }
}
