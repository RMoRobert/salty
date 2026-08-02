//
//  SyncThrottleTests.swift
//  SaltyTests
//
//  Covers the recently-synced guard: rapid repeat triggers (pull-to-refresh on top of an automatic
//  sync, a mashed menu shortcut) must be skipped, a deliberate force (Settings' Sync Now) must not,
//  and a clock that moved backwards must never block syncing.
//

import Testing
import Foundation
@testable import Salty

struct SyncThrottleTests {

    /// Fixed reference point so boundary cases don't depend on wall-clock timing.
    let now = Date(timeIntervalSince1970: 1_800_000_000)

    @Test func skipsWhenSyncJustFinished() {
        let justSynced = now.addingTimeInterval(-5)
        #expect(SaltySyncService.shouldThrottleSync(lastSuccessfulSync: justSynced, now: now, force: false))
    }

    @Test func skipsJustInsideTheWindow() {
        let inside = now.addingTimeInterval(-(SaltySyncService.minimumSyncInterval - 1))
        #expect(SaltySyncService.shouldThrottleSync(lastSuccessfulSync: inside, now: now, force: false))
    }

    @Test func syncsAtTheWindowBoundary() {
        let boundary = now.addingTimeInterval(-SaltySyncService.minimumSyncInterval)
        #expect(!SaltySyncService.shouldThrottleSync(lastSuccessfulSync: boundary, now: now, force: false))
    }

    @Test func syncsWhenLastSyncIsOld() {
        let old = now.addingTimeInterval(-3600)
        #expect(!SaltySyncService.shouldThrottleSync(lastSuccessfulSync: old, now: now, force: false))
    }

    @Test func syncsWhenNeverSynced() {
        #expect(!SaltySyncService.shouldThrottleSync(lastSuccessfulSync: nil, now: now, force: false))
    }

    @Test func forceBypassesTheGuard() {
        let justSynced = now.addingTimeInterval(-5)
        #expect(!SaltySyncService.shouldThrottleSync(lastSuccessfulSync: justSynced, now: now, force: true))
    }

    /// A last-sync time in the future means the clock moved backwards (time zone change, manual clock
    /// edit, a restored backup). Sync rather than refuse based on a nonsense interval.
    @Test func syncsWhenClockMovedBackwards() {
        let future = now.addingTimeInterval(60)
        #expect(!SaltySyncService.shouldThrottleSync(lastSuccessfulSync: future, now: now, force: false))
    }
}
