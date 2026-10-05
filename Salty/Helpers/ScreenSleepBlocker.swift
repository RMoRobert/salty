//
//  ScreenSleepBlocker.swift
//  Salty
//
//  Keeps the display awake while Chef View is open — a recipe you're cooking from is useless if
//  the screen dims halfway through kneading. Several holders at once are fine (macOS can have
//  several Chef View windows open; on iOS a mirroring TV holds it alongside the phone's own view).
//

import Foundation
#if !os(macOS)
import UIKit
#endif

@MainActor
final class ScreenSleepBlocker {
    static let shared = ScreenSleepBlocker()

    private init() {}

    /// One holder's claim on the display. Hand it back with `release(_:)`.
    ///
    /// A claim rather than a bare counter: SwiftUI can fire `onAppear` twice for one appearance (the
    /// list editors document this), and a counter bumped twice but decremented once left the screen
    /// awake for the rest of the session. Releasing the same claim twice, or holding when a claim is
    /// already held, does nothing.
    final class Hold: Sendable {
        fileprivate let id = UUID()
        fileprivate init() {}
    }

    private var holds: Set<UUID> = []

    #if os(macOS)
    private var activity: (any NSObjectProtocol)?
    #endif

    /// Takes a claim on the display; the first claim switches idle sleep off.
    func hold() -> Hold {
        let hold = Hold()
        let wasHeld = !holds.isEmpty
        holds.insert(hold.id)
        if !wasHeld {
            keepAwake()
        }
        return hold
    }

    /// Gives a claim back; the last one switches idle sleep on again.
    func release(_ hold: Hold) {
        guard holds.remove(hold.id) != nil, holds.isEmpty else { return }
        allowSleep()
    }

    private func keepAwake() {
        #if os(macOS)
        activity = ProcessInfo.processInfo.beginActivity(
            options: .idleDisplaySleepDisabled,
            reason: "Chef View is displaying a recipe while cooking"
        )
        #else
        UIApplication.shared.isIdleTimerDisabled = true
        #endif
    }

    private func allowSleep() {
        #if os(macOS)
        if let activity {
            ProcessInfo.processInfo.endActivity(activity)
        }
        activity = nil
        #else
        UIApplication.shared.isIdleTimerDisabled = false
        #endif
    }
}
