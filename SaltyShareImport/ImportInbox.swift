//
//  ImportInbox.swift
//  Salty (app and SaltyShareExtension)
//
//  Pages shared to Salty from the iOS share sheet, waiting for the app to open them.
//
//  A share extension isn't allowed to open its app (there is no supported way; see the Apple forum
//  threads behind FEATURE_PLANS "Browser hand-off"), so the extension leaves the page's address here,
//  in the App Group container both it and the app can reach, and says "Sent to Salty". The app takes
//  the pages out one at a time -- when it comes to the front, and as each import closes -- and opens
//  Web Import on them (see `MainView`). macOS needs none of this: its extension opens the
//  `salty://import` link directly.
//

#if os(iOS)
import Foundation

enum ImportInbox {
    /// The App Group the app and the extension share, read from each bundle's Info.plist (`SaltyAppGroup`,
    /// set from the `SALTY_APP_GROUP` build setting, so Debug and Release builds keep separate inboxes).
    static var appGroupID: String? {
        Bundle.main.object(forInfoDictionaryKey: "SaltyAppGroup") as? String
    }

    private static let pagesKey = "pendingImportPages"

    private static var defaults: UserDefaults? {
        appGroupID.flatMap { UserDefaults(suiteName: $0) }
    }

    /// Queues a page for the app to open. Called by the share extension.
    static func append(_ page: URL) {
        guard let defaults else { return }
        var pages = defaults.stringArray(forKey: pagesKey) ?? []
        pages.append(page.absoluteString)
        defaults.set(pages, forKey: pagesKey)
    }

    /// Removes and returns the page that has waited longest, or nil when none is waiting.
    static func takeNext() -> URL? {
        guard let defaults, var pages = defaults.stringArray(forKey: pagesKey), !pages.isEmpty else {
            return nil
        }
        let next = pages.removeFirst()
        if pages.isEmpty {
            defaults.removeObject(forKey: pagesKey)
        } else {
            defaults.set(pages, forKey: pagesKey)
        }
        return URL(string: next)
    }
}
#endif
