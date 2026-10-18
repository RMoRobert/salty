//
//  OpenRecipeIntent.swift
//  Salty
//
//  The "Open Recipe" action in Shortcuts (and so Siri, and Automator's Run Shortcut action): brings
//  Salty forward showing the chosen recipe. An `OpenIntent`, the system's own kind for "open this
//  item", so it is also what Spotlight would use once recipes are indexed there.
//
//  The system brings the app forward before perform() runs, in the app's process; perform() then
//  leaves the recipe's link in `SaltyLinkInbox`, and the frontmost main window opens it as it would
//  a pasted private link. (Returning `OpenURLIntent` on the link is refused for a custom scheme, and
//  `URLRepresentableIntent`, which would need no perform() at all, takes universal links only.)
//

import AppIntents

struct OpenRecipeIntent: OpenIntent {
    static let title: LocalizedStringResource = "Open Recipe"
    static let description = IntentDescription(
        "Opens a recipe from your Salty library.",
        categoryName: "Recipes"
    )

    @Parameter(title: "Recipe", description: "The recipe to show.")
    var target: RecipeEntity

    static var parameterSummary: some ParameterSummary {
        Summary("Open \(\.$target)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        SaltyLinkInbox.shared.request(.recipe(id: target.id))
        return .result()
    }
}
