//
//  ImportRecipeFromWebIntent.swift
//  Salty
//
//  The "Import Recipe from Web" action in Shortcuts (and so Siri and Spotlight): takes a page's
//  address and opens Web Import on it. On iOS this is the supported way to put Salty in the share
//  sheet -- a one-action shortcut set to accept URLs from the share sheet -- since a share extension
//  isn't allowed to open its app. The system brings the app forward, then perform() leaves the
//  page's `salty://import` link in `SaltyLinkInbox` for the frontmost window, which opens it exactly
//  as it opens the link a bookmarklet sends -- one entry point to keep working. (It used to return
//  `OpenURLIntent` on that link, which Shortcuts refuses for a custom scheme; see SaltyLinkInbox.)
//

import AppIntents

struct ImportRecipeFromWebIntent: AppIntent {
    static let title: LocalizedStringResource = "Import Recipe from Web"
    static let description = IntentDescription(
        "Opens Salty's Web Import on a recipe web page and scans it for a recipe.",
        categoryName: "Recipes"
    )

    /// Web Import is a window in the app, so the app has to come forward. Both spellings: OS 26 reads
    /// `supportedModes`, earlier systems `openAppWhenRun`.
    static let openAppWhenRun = true

    @available(iOS 26.0, macOS 26.0, *)
    static var supportedModes: IntentModes { .foreground }

    @Parameter(title: "Web Page", description: "The address of the recipe page.")
    var page: URL

    static var parameterSummary: some ParameterSummary {
        Summary("Import recipe from \(\.$page)")
    }

    @MainActor
    func perform() async throws -> some IntentResult {
        // Shortcuts can hand over anything that is a URL; only a web page can be imported.
        guard let link = SaltyURL.importLink(for: page) else {
            throw NotAWebPageError()
        }
        SaltyLinkInbox.shared.request(link)
        return .result()
    }
}

/// Shortcuts shows this when the action is handed something other than a web page.
private struct NotAWebPageError: Error, CustomLocalizedStringResourceConvertible {
    var localizedStringResource: LocalizedStringResource {
        "Salty can only import from a web page (an http or https address)."
    }
}
