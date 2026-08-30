//
//  ExternalDisplaySceneDelegate.swift
//  Salty
//
//  Hosts the TV's content when Screen Mirroring hands the app the external display.
//
//  The window's root is SwiftUI (ExternalChefDisplayView); this class is only the UIKit shim that
//  the scene system requires — see SaltyAppDelegate for why the shim exists at all. The scene is
//  non-interactive by definition: nothing here receives touches, it purely displays.
//
//  Two side effects are tied to the scene's lifetime:
//
//  - ScreenSleepBlocker: the phone sleeping ends the whole AirPlay session, so the display must be
//    held awake for as long as the TV is connected — not just while the phone's own Chef View is
//    open. (The blocker is reference-counted; this pairs with the phone's own begin/end.)
//  - The coordinator's connected flag, so the phone UI can know a TV is showing.
//
//  The session store is injected explicitly (`ChefViewSessionStore.shared`) rather than through
//  SwiftUI's environment, because this window sits outside the App's scene hierarchy — that's the
//  reason the store is reachable as a shared instance at all.
//

#if !os(macOS)

import UIKit
import SwiftUI
import OSLog

@MainActor
final class ExternalDisplaySceneDelegate: NSObject, UIWindowSceneDelegate {
    private let logger = Logger(subsystem: "Salty", category: "ExternalDisplay")

    var window: UIWindow?

    func scene(
        _ scene: UIScene,
        willConnectTo session: UISceneSession,
        options connectionOptions: UIScene.ConnectionOptions
    ) {
        guard let windowScene = scene as? UIWindowScene else { return }
        logger.info("External display scene connecting: \(windowScene.screen.bounds.width, format: .fixed(precision: 0))×\(windowScene.screen.bounds.height, format: .fixed(precision: 0))")

        let window = UIWindow(windowScene: windowScene)
        let root = ExternalChefDisplayView()
            .environment(ChefViewSessionStore.shared)
        window.rootViewController = UIHostingController(rootView: root)
        self.window = window
        window.isHidden = false

        ScreenSleepBlocker.shared.begin()
        ChefExternalDisplayCoordinator.shared.externalSceneDidConnect()
    }

    func sceneDidDisconnect(_ scene: UIScene) {
        ScreenSleepBlocker.shared.end()
        ChefExternalDisplayCoordinator.shared.externalSceneDidDisconnect()
        window = nil
    }
}

#endif
