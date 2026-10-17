//
//  ImportRecipeFromWebIntent.swift
//  Salty
//
//  The "Import Recipe from Web" action in Shortcuts (and so Siri and Spotlight): takes a page's
//  address and opens Web Import on it. On iOS this is the supported way to put Salty in the share
//  sheet -- a one-action shortcut set to accept URLs from the share sheet -- since a share extension
//  isn't allowed to open its app. It opens the app through the same `salty://import` link a
//  bookmarklet uses, so there is one entry point to keep working.
//

import AppIntents

struct ImportRecipeFromWebIntent: AppIntent {
    static let title: LocalizedStringResource = "Import Recipe from Web"
    static let description = IntentDescription(
        "Opens Salty's Web Import on a recipe web page and scans it for a recipe.",
        categoryName: "Recipes"
    )

    @Parameter(title: "Web Page", description: "The address of the recipe page.")
    var page: URL

    static var parameterSummary: some ParameterSummary {
        Summary("Import recipe from \(\.$page)")
    }

    func perform() async throws -> some IntentResult & OpensIntent {
        // Shortcuts can hand over anything that is a URL; only a web page can be imported.
        guard let link = SaltyURL.importLink(for: page) else {
            throw NotAWebPageError()
        }
        return .result(opensIntent: OpenURLIntent(link.url))
    }
}

/// Shortcuts shows this when the action is handed something other than a web page.
private struct NotAWebPageError: Error, CustomLocalizedStringResourceConvertible {
    var localizedStringResource: LocalizedStringResource {
        "Salty can only import from a web page (an http or https address)."
    }
}
