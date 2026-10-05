//
//  AppRelauncher.swift
//  Salty
//
//  Restarts Salty on the Mac, so a newly chosen library folder takes effect without the user having to
//  quit and reopen it themselves. iOS has no equivalent: an app may not quit itself there.
//

import Foundation
import OSLog
#if os(macOS)
import AppKit
#endif

enum AppRelauncher {
    /// Whether this platform can restart the app on request.
    static var isAvailable: Bool {
        #if os(macOS)
        true
        #else
        false
        #endif
    }

    /// Opens a fresh copy of the app, then quits this one once the new copy is launching. The new
    /// copy reads the library location at startup; this one checkpoints its database as it quits.
    /// If the new copy can't be launched, this one keeps running and the failure is logged.
    @MainActor
    static func relaunch() async {
        #if os(macOS)
        let logger = Logger(subsystem: "Salty", category: "App")
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.createsNewApplicationInstance = true
        configuration.activates = true
        do {
            _ = try await NSWorkspace.shared.openApplication(at: Bundle.main.bundleURL, configuration: configuration)
            NSApplication.shared.terminate(nil)
        } catch {
            logger.error("Relaunch failed: \(error.localizedDescription)")
        }
        #endif
    }
}
