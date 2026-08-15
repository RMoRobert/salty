//
//  RecipeSyncReconcilerTests.swift
//  SaltyTests
//
//  Exhaustive tests for the pure recipe sync diff. This is the data-loss-critical logic: getting the
//  deletion branches wrong wipes recipes, so every case is pinned here.
//

import Testing
import Foundation
@testable import Salty
import SaltyCore

struct RecipeSyncReconcilerTests {

    private func date(_ t: Double) -> Date { Date(timeIntervalSince1970: t) }
    private func e(_ id: String, _ t: Double) -> RecipeSyncReconciler.Entry {
        RecipeSyncReconciler.Entry(id: id, lastModified: date(t))
    }

    // MARK: - First sync

    @Test func firstSyncUploadsLocalOnlyAndDownloadsServerOnly() {
        let plan = RecipeSyncReconciler.plan(
            local: [e("a", 100)],
            server: [e("b", 100)],
            isFirstSync: true,
            lastSyncDate: nil
        )
        #expect(plan.toUpload == ["a"])
        #expect(plan.toDownload == ["b"])
        #expect(plan.toDeleteLocally.isEmpty)
        #expect(plan.toDeleteOnServer.isEmpty)
    }

    // MARK: - Present on both sides → newer wins

    @Test func bothSidesLocalNewerUploads() {
        let plan = RecipeSyncReconciler.plan(local: [e("a", 200)], server: [e("a", 100)],
                                             isFirstSync: false, lastSyncDate: date(150))
        #expect(plan.toUpload == ["a"])
        #expect(plan.toDownload.isEmpty)
        #expect(plan.toDeleteLocally.isEmpty && plan.toDeleteOnServer.isEmpty)
    }

    @Test func bothSidesServerNewerDownloads() {
        let plan = RecipeSyncReconciler.plan(local: [e("a", 100)], server: [e("a", 200)],
                                             isFirstSync: false, lastSyncDate: date(150))
        #expect(plan.toDownload == ["a"])
        #expect(plan.toUpload.isEmpty)
        #expect(plan.toDeleteLocally.isEmpty && plan.toDeleteOnServer.isEmpty)
    }

    @Test func bothSidesEqualIsNoOp() {
        let plan = RecipeSyncReconciler.plan(local: [e("a", 100)], server: [e("a", 100)],
                                             isFirstSync: false, lastSyncDate: date(150))
        #expect(plan == RecipeSyncReconciler.Plan())
    }

    // MARK: - Only local (relative to lastSync)

    @Test func onlyLocalNewerThanLastSyncUploads() {
        let plan = RecipeSyncReconciler.plan(local: [e("a", 200)], server: [],
                                             isFirstSync: false, lastSyncDate: date(150))
        #expect(plan.toUpload == ["a"])
        #expect(plan.toDeleteLocally.isEmpty)
    }

    @Test func onlyLocalOlderThanLastSyncIsDeletedOnServer() {
        // Existed before last sync, now gone from the server's manifest → it was deleted elsewhere.
        let plan = RecipeSyncReconciler.plan(local: [e("a", 100)], server: [],
                                             isFirstSync: false, lastSyncDate: date(150))
        #expect(plan.toDeleteLocally == ["a"])
        #expect(plan.toUpload.isEmpty)
    }

    // MARK: - Only server (relative to lastSync)

    @Test func onlyServerNewerThanLastSyncDownloads() {
        let plan = RecipeSyncReconciler.plan(local: [], server: [e("b", 200)],
                                             isFirstSync: false, lastSyncDate: date(150))
        #expect(plan.toDownload == ["b"])
        #expect(plan.toDeleteOnServer.isEmpty)
    }

    @Test func onlyServerOlderThanLastSyncIsDeletedLocally_soDeleteOnServer() {
        let plan = RecipeSyncReconciler.plan(local: [], server: [e("b", 100)],
                                             isFirstSync: false, lastSyncDate: date(150))
        #expect(plan.toDeleteOnServer == ["b"])
        #expect(plan.toDownload.isEmpty)
    }

    @Test func serverMissingTimestampMappedToDistantPastIsTreatedAsOld() {
        // The caller maps a nil manifest timestamp to .distantPast; with a lastSync set that means
        // "existed before last sync, gone locally" → delete on server.
        let plan = RecipeSyncReconciler.plan(local: [], server: [e2("b", .distantPast)],
                                             isFirstSync: false, lastSyncDate: date(150))
        #expect(plan.toDeleteOnServer == ["b"])
    }

    // MARK: - Safety: no lastSyncDate (and not first sync) never deletes

    @Test func nilLastSyncNotFirstSyncTreatsOrphansAsNewNeverDeletes() {
        let plan = RecipeSyncReconciler.plan(local: [e("a", 100)], server: [e("b", 100)],
                                             isFirstSync: false, lastSyncDate: nil)
        #expect(plan.toUpload == ["a"])
        #expect(plan.toDownload == ["b"])
        #expect(plan.toDeleteLocally.isEmpty && plan.toDeleteOnServer.isEmpty)
    }

    // MARK: - Mixed realistic batch

    @Test func mixedBatchRoutesEachRecipeCorrectly() {
        let plan = RecipeSyncReconciler.plan(
            local: [e("same", 100), e("localNewer", 200), e("newLocal", 300), e("goneOnServer", 50)],
            server: [e("same", 100), e("localNewer", 100), e("serverNewer", 300), e("goneLocally", 40)],
            isFirstSync: false,
            lastSyncDate: date(150)
        )
        #expect(Set(plan.toUpload) == ["localNewer", "newLocal"])
        #expect(Set(plan.toDownload) == ["serverNewer"])
        #expect(Set(plan.toDeleteLocally) == ["goneOnServer"])
        #expect(Set(plan.toDeleteOnServer) == ["goneLocally"])
    }

    private func e2(_ id: String, _ d: Date) -> RecipeSyncReconciler.Entry {
        RecipeSyncReconciler.Entry(id: id, lastModified: d)
    }
}
