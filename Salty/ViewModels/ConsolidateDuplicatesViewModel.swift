//
//  ConsolidateDuplicatesViewModel.swift
//  Salty
//
//  Backs ConsolidateDuplicatesView: scans the library for categories, courses, and tags that share a
//  name and merges the groups the user picks. All the actual logic lives in LibraryDuplicateFinder /
//  LibraryDuplicateMerger; this only holds view state and moves work on and off the database.
//

import Foundation
import OSLog
import SQLiteData
import SaltyCore

@Observable
@MainActor
final class ConsolidateDuplicatesViewModel {
    private let logger = Logger(subsystem: "Salty", category: "Library")

    @ObservationIgnored
    @Dependency(\.defaultDatabase) private var database

    /// Duplicate groups from the most recent scan, categories first, then courses, then tags.
    private(set) var groups: [LibraryDuplicateGroup] = []
    /// Which groups the merge applies to. Everything found is selected by default.
    var selectedGroupIDs: Set<String> = []
    private(set) var isWorking = false
    /// False until the first scan finishes, so the empty state isn't shown before there's an answer.
    private(set) var hasScanned = false
    /// Result of the last merge, shown as a confirmation of what changed.
    var lastMergeSummary: LibraryDuplicateMerger.Summary?
    var showingMergeConfirmation = false
    /// Set when a scan or merge fails; surfaced via `.errorAlert`.
    var operationError: String?

    // MARK: - Derived state

    var groupsByKind: [(kind: LibraryClassifier, groups: [LibraryDuplicateGroup])] {
        LibraryClassifier.allCases.compactMap { kind in
            let matching = groups.filter { $0.kind == kind }
            return matching.isEmpty ? nil : (kind, matching)
        }
    }

    var selectedGroups: [LibraryDuplicateGroup] {
        groups.filter { selectedGroupIDs.contains($0.id) }
    }

    var canMerge: Bool { !selectedGroups.isEmpty && !isWorking }

    /// How many rows "Merge" would delete — the number worth showing in the confirmation.
    var selectedRemovalCount: Int {
        selectedGroups.reduce(0) { $0 + $1.removedCount }
    }

    // MARK: - Actions

    func isSelected(_ group: LibraryDuplicateGroup) -> Bool {
        selectedGroupIDs.contains(group.id)
    }

    func setSelected(_ group: LibraryDuplicateGroup, _ isSelected: Bool) {
        if isSelected {
            selectedGroupIDs.insert(group.id)
        } else {
            selectedGroupIDs.remove(group.id)
        }
    }

    func selectAll() {
        selectedGroupIDs = Set(groups.map(\.id))
    }

    func deselectAll() {
        selectedGroupIDs.removeAll()
    }

    /// Re-reads the library and rebuilds the duplicate groups, preserving the current selection where
    /// the groups still exist (a merge re-scans, and merged groups simply disappear).
    func scan() async {
        isWorking = true
        defer { isWorking = false }
        do {
            let found = try await database.read { db in
                try LibraryDuplicateMerger.duplicateGroups(in: db)
            }
            let previousSelection = hasScanned ? selectedGroupIDs : nil
            groups = found
            selectedGroupIDs = previousSelection.map { previous in
                Set(found.map(\.id).filter(previous.contains))
            } ?? Set(found.map(\.id))
            hasScanned = true
        } catch {
            logger.error("Error scanning for duplicate library items: \(error)")
            operationError = "Couldn’t scan the library for duplicates. \(error.localizedDescription)"
        }
    }

    /// Merges every selected group in one transaction, then re-scans so the list reflects the result.
    func mergeSelected() async {
        let toMerge = selectedGroups
        guard !toMerge.isEmpty else { return }
        isWorking = true
        do {
            let summary = try await database.write { db in
                try LibraryDuplicateMerger.merge(toMerge, in: db)
            }
            isWorking = false
            lastMergeSummary = summary
            await scan()
        } catch {
            isWorking = false
            logger.error("Error merging duplicate library items: \(error)")
            operationError = "Couldn’t merge the duplicates. \(error.localizedDescription)"
        }
    }
}
