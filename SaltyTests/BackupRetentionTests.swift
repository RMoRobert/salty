//
//  BackupRetentionTests.swift
//  SaltyTests
//
//  The backup retention policy, run against synthetic backup ages so no files are involved.
//
//  The policy used to be "newest, plus one at least 5 days older, plus one 20 days older than that",
//  which sounds fine and never worked: a backup is taken every ~36 hours, so the 36-hour-old one was
//  never old enough to qualify and was deleted -- every run -- before it could age into the 5-day
//  slot. The app held two backups a day and a half apart, and nothing older. These tests pin the
//  properties the replacement policy has to have.
//

import Testing
import Foundation
@testable import Salty

struct BackupRetentionTests {

    private let day: TimeInterval = 24 * 60 * 60
    private let hour: TimeInterval = 60 * 60

    /// Runs the policy over a simulated history: a backup every `interval`, cleaned up after each one,
    /// and returns the ages (in days, newest first) of what survives at the end.
    private func simulate(interval: TimeInterval, runs: Int) -> [Double] {
        var kept: [TimeInterval] = []   // absolute times of surviving backups
        var now: TimeInterval = 0
        for _ in 0..<runs {
            kept.append(now)
            kept.sort(by: >)
            let ages = kept.map { now - $0 }
            let keep = DatabaseBackupManager.retainedBackupIndices(ages: ages)
            kept = kept.enumerated().filter { keep.contains($0.offset) }.map(\.element)
            now += interval
        }
        let newest = kept.max() ?? 0
        return kept.sorted(by: >).map { (newest - $0) / day }
    }

    @Test func nothingToKeepWhenThereAreNoBackups() {
        #expect(DatabaseBackupManager.retainedBackupIndices(ages: []).isEmpty)
    }

    @Test func theNewestBackupsAreAlwaysKept() {
        // Five backups a minute apart: nothing is old enough for any band beyond the first.
        let ages = (0..<5).map { TimeInterval($0 * 60) }
        let keep = DatabaseBackupManager.retainedBackupIndices(ages: ages)
        for index in 0..<DatabaseBackupManager.recentBackupsToKeep {
            #expect(keep.contains(index))
        }
    }

    /// The bug the rewrite exists for: with a backup every 36 hours, older tiers must fill.
    @Test func frequentBackupsStillAgeIntoTheOlderTiers() {
        let survivors = simulate(interval: 36 * hour, runs: 40)   // 60 days of history
        #expect(survivors.contains { $0 >= 5 && $0 < 20 }, "a backup between 5 and 20 days old must survive")
        #expect(survivors.contains { $0 >= 20 }, "a backup at least 20 days old must survive")
    }

    /// Retention stays bounded: one survivor per band plus the recent ones, never a growing pile.
    @Test func theNumberOfBackupsIsBounded() {
        let bound = DatabaseBackupManager.recentBackupsToKeep + DatabaseBackupManager.retentionBandBoundaries.count + 1
        #expect(simulate(interval: 36 * hour, runs: 60).count <= bound)
        #expect(simulate(interval: 7 * day, runs: 30).count <= bound)
        #expect(simulate(interval: 3 * hour, runs: 200).count <= bound)
    }

    /// The oldest band keeps its newest member, so the very first backup ever taken does not
    /// survive forever once younger backups have aged past the boundary.
    @Test func theOldestBandRollsForward() {
        let survivors = simulate(interval: 7 * day, runs: 30)   // 30 weekly backups
        let oldest = survivors.max() ?? 0
        #expect(oldest < 40, "a 200-day-old backup should long since have rolled off; oldest is \(oldest) days")
    }

    /// The scenario from the review: data goes bad, and the next two launches each take a backup of
    /// the bad state. A good backup must still be there afterwards.
    @Test func aGoodBackupSurvivesTwoLaunchesAfterCorruption() {
        // Ages, newest first, in seconds: two "bad" backups then the pre-corruption ones.
        let ages: [TimeInterval] = [0, 36 * hour, 72 * hour, 108 * hour, 144 * hour]
        let keep = DatabaseBackupManager.retainedBackupIndices(ages: ages)
        #expect(keep.contains(2) || keep.contains(3) || keep.contains(4), "at least one pre-corruption backup must survive")
    }
}
