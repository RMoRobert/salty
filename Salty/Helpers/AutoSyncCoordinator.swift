//
//  AutoSyncCoordinator.swift
//  Salty
//
//  Drives the optional "Sync automatically" feature:
//   • debounced upload after local edits cease (watches the database, so any edit path counts),
//   • catch-up sync on launch and on return-to-foreground (throttled),
//   • best-effort flush when the app backgrounds (expedite before suspension),
//   • silent on transient failures; a dismissable banner appears only after several in a row.
//  Manual sync (Settings → Sync Now) is unaffected and still surfaces every error.
//
//  Enabled by the `autoSyncEnabled` UserDefaults flag (Settings toggle, default off). When off, the
//  database observation stays installed but every callback returns immediately, so overhead is nil.
//

import Foundation
import SQLiteData
import GRDB
import OSLog
#if canImport(UIKit)
import UIKit
#elseif canImport(AppKit)
import AppKit
#endif

@MainActor
@Observable
final class AutoSyncCoordinator {
    static let shared = AutoSyncCoordinator()

    // MARK: Tunables
    /// How long edits must be quiet before an upload fires (coalesces rapid successive edits).
    private let quietPeriod: Duration = .seconds(90)
    /// Don't run another foreground catch-up sync within this window (so app-switching doesn't spam).
    private let foregroundThrottle: TimeInterval = 5 * 60
    /// Consecutive auto-sync failures before the user-facing banner appears.
    private let failureThreshold = 3

    /// Bound by `MainView` — shown after repeated auto-sync failures; user-dismissable.
    var showFailureBanner = false

    /// When auto-sync is paused until (persisted), or nil if not paused. Manual sync is never paused.
    private(set) var pausedUntil: Date?

    /// Auto-sync is currently suppressed by a user-initiated pause.
    var isPaused: Bool {
        if let pausedUntil { return pausedUntil > Date() }
        return false
    }

    @ObservationIgnored private let logger = Logger(subsystem: "Salty", category: "AutoSync")
    @ObservationIgnored @Dependency(\.defaultDatabase) private var database
    @ObservationIgnored private let syncService = SaltySyncService.shared

    @ObservationIgnored private var started = false
    @ObservationIgnored private var observationCancellable: AnyDatabaseCancellable?
    @ObservationIgnored private var debounceTask: Task<Void, Never>?
    @ObservationIgnored private var hasPendingLocalChanges = false
    @ObservationIgnored private var consecutiveFailures = 0
    @ObservationIgnored private var lastAttempt: Date?

    private var isEnabled: Bool { UserDefaults.standard.bool(forKey: "autoSyncEnabled") }
    private static let pausedUntilKey = "autoSyncPausedUntil"

    private init() {
        pausedUntil = UserDefaults.standard.object(forKey: Self.pausedUntilKey) as? Date
    }

    // MARK: - Lifecycle entry points

    /// Start watching the database for local edits. Idempotent; call once from `MainView.task`.
    func start() {
        guard !started else { return }
        started = true
        let observation = DatabaseRegionObservation(tracking: .fullDatabase)
        observationCancellable = observation.start(
            in: database,
            onError: { [weak self] error in
                self?.logger.error("Database observation error: \(error)")
            },
            onChange: { [weak self] _ in
                // Fires on the writer queue after each commit; hop to the main actor to react.
                Task { @MainActor in self?.localDataDidChange() }
            }
        )
    }

    /// App launched or returned to the foreground: pull server-side changes, unless we synced recently.
    func appBecameActive() async {
        guard isEnabled, !isPaused else { return }
        if let last = lastAttempt, Date().timeIntervalSince(last) < foregroundThrottle { return }
        await performAutoSync(reason: "foreground")
    }

    /// App is backgrounding: flush unsynced local edits best-effort, before the OS may suspend us.
    func appWillBackground() {
        guard isEnabled, !isPaused, hasPendingLocalChanges else { return }
        debounceTask?.cancel()
        debounceTask = nil
        #if canImport(UIKit)
        // Ask iOS for a little time to finish the in-flight upload after we leave the foreground.
        var bgTask: UIBackgroundTaskIdentifier = .invalid
        bgTask = UIApplication.shared.beginBackgroundTask(withName: "Salty.AutoSyncFlush") {
            if bgTask != .invalid { UIApplication.shared.endBackgroundTask(bgTask); bgTask = .invalid }
        }
        Task { @MainActor in
            await performAutoSync(reason: "background")
            if bgTask != .invalid { UIApplication.shared.endBackgroundTask(bgTask); bgTask = .invalid }
        }
        #else
        Task { @MainActor in await performAutoSync(reason: "background") }
        #endif
    }

    func dismissFailureBanner() { showFailureBanner = false }

    /// "Retry" from the failure banner.
    func retryNow() async { await performAutoSync(reason: "manual-retry") }

    /// Pause automatic sync for 24 hours (offered on the failure banner). Manual sync still works, the
    /// pause survives relaunch, and it clears itself once the time passes or via `resume()`.
    func pauseForOneDay() {
        setPaused(until: Date().addingTimeInterval(24 * 60 * 60))
        debounceTask?.cancel()
        debounceTask = nil
        consecutiveFailures = 0
        showFailureBanner = false
        logger.info("Auto-sync paused for 1 day")
    }

    /// Clear an active pause and allow automatic sync again.
    func resume() {
        setPaused(until: nil)
        logger.info("Auto-sync resumed")
    }

    private func setPaused(until date: Date?) {
        pausedUntil = date
        if let date {
            UserDefaults.standard.set(date, forKey: Self.pausedUntilKey)
        } else {
            UserDefaults.standard.removeObject(forKey: Self.pausedUntilKey)
        }
    }

    // MARK: - Internals

    private func localDataDidChange() {
        guard isEnabled, !isPaused else { return }
        // Ignore the writes sync itself makes while applying server changes — otherwise it could loop.
        guard !syncService.isSyncing else { return }
        hasPendingLocalChanges = true
        scheduleDebouncedSync()
    }

    private func scheduleDebouncedSync() {
        debounceTask?.cancel()
        debounceTask = Task { @MainActor [weak self] in
            guard let self else { return }
            try? await Task.sleep(for: self.quietPeriod)
            if Task.isCancelled { return }
            self.debounceTask = nil
            await self.performAutoSync(reason: "edit")
        }
    }

    private func performAutoSync(reason: String) async {
        guard isEnabled, !isPaused, !syncService.isSyncing else { return }
        lastAttempt = Date()
        logger.info("Auto-sync starting (\(reason))")
        do {
            try await syncService.syncNow()
            consecutiveFailures = 0
            hasPendingLocalChanges = false
            showFailureBanner = false
            logger.info("Auto-sync succeeded (\(reason))")
        } catch SyncError.serverNotConfigured, SyncError.credentialsNotConfigured {
            // Server/credentials not set up (e.g. password not saved to Keychain) → auto-sync is simply
            // not applicable here. Not a connectivity failure, so don't count it or alarm the user.
            logger.info("Auto-sync skipped (\(reason)): server/credentials not configured")
        } catch {
            consecutiveFailures += 1
            logger.warning("Auto-sync failed (\(reason)) [\(self.consecutiveFailures)x]: \(error)")
            if consecutiveFailures >= failureThreshold { showFailureBanner = true }
        }
    }
}
