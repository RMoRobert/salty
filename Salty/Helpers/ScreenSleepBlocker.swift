//
//  ScreenSleepBlocker.swift
//  Salty
//
//  Keeps the display awake while Chef View is open — a recipe you're cooking from is useless if
//  the screen dims halfway through kneading. Reference counted, because macOS can have several
//  Chef View windows open at once.
//

import Foundation
#if !os(macOS)
import UIKit
#endif

@MainActor
final class ScreenSleepBlocker {
    static let shared = ScreenSleepBlocker()

    private init() {}

    private var holders = 0

    #if os(macOS)
    private var activity: (any NSObjectProtocol)?
    #endif

    /// Balanced by `end()`. Callers must pair these on appear/disappear — the display is left
    /// awake for exactly as long as something is holding it.
    func begin() {
        holders += 1
        guard holders == 1 else { return }
        #if os(macOS)
        activity = ProcessInfo.processInfo.beginActivity(
            options: .idleDisplaySleepDisabled,
            reason: "Chef View is displaying a recipe while cooking"
        )
        #else
        UIApplication.shared.isIdleTimerDisabled = true
        #endif
    }

    func end() {
        holders = max(0, holders - 1)
        guard holders == 0 else { return }
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
