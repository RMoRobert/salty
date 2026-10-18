//
//  SaltyLinkInbox.swift
//  Salty
//
//  `salty://` requests made inside the app itself -- by an App Intent's perform() (Open Recipe,
//  Import Recipe from Web) -- waiting for the frontmost main window to act on them exactly as it
//  acts on a link it was opened with (`MainView.open(_:)`), so both routes share one handler and one
//  "isn't in this library" alert.
//
//  Why intents don't simply return `OpenURLIntent` on the link: Shortcuts refuses to launch a custom
//  scheme from an intent's result ("The provided URL scheme `salty` is unsupported; launch is
//  prohibited", seen on the iOS 27 simulator, 2026-10-17). An intent that opens the app runs its
//  perform() in the app's own process anyway, so it hands the request over here instead.
//

import Observation

@MainActor
@Observable
final class SaltyLinkInbox {
    static let shared = SaltyLinkInbox()

    /// The request waiting for a window, if any. A newer request replaces an unopened one: only the
    /// last thing asked for is still wanted.
    private(set) var pending: SaltyURL?

    /// Leaves `link` for the frontmost main window.
    func request(_ link: SaltyURL) {
        pending = link
    }

    /// Removes and returns the waiting request, so exactly one window acts on it.
    func take() -> SaltyURL? {
        guard let link = pending else { return nil }
        pending = nil
        return link
    }
}
