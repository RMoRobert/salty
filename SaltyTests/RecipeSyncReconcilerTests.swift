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

    // MARK: - SHARED-V0005: agreement bookkeeping replaces the local-only guess

    /// A local entry that HAS been agreed with the server.
    private func agreed(_ id: String, _ t: Double, synced: Double? = nil) -> RecipeSyncReconciler.Entry {
        RecipeSyncReconciler.Entry(id: id, lastModified: date(t), syncedModified: date(synced ?? t))
    }

    private func tracked(
        local: [RecipeSyncReconciler.Entry],
        server: [RecipeSyncReconciler.Entry],
        lastSyncDate: Date?
    ) -> RecipeSyncReconciler.Plan {
        RecipeSyncReconciler.plan(
            local: local, server: server, isFirstSync: false, lastSyncDate: lastSyncDate, tracksAgreement: true
        )
    }

    /// The bug the column exists for. A recipe imported from a file exported years ago carries an
    /// ancient `lastModifiedDate`, so the watermark rule reads it as "existed before the last sync,
    /// gone on the server" and DELETES it. It has simply never been to the server.
    @Test func anOldRowThatWasNeverAgreedIsUploadedNotDeleted() {
        let plan = tracked(local: [e("imported", 1)], server: [], lastSyncDate: date(1_000_000))
        #expect(plan.toUpload == ["imported"])
        #expect(plan.toDeleteLocally.isEmpty)
    }

    /// The other half: a row that WAS agreed and is now absent really was deleted there.
    @Test func aRowThatWasAgreedAndIsNowAbsentIsDeletedLocally() {
        let plan = tracked(local: [agreed("gone", 100)], server: [], lastSyncDate: date(1_000_000))
        #expect(plan.toDeleteLocally == ["gone"])
        #expect(plan.toUpload.isEmpty)
    }

    /// Delete-vs-edit is a genuine conflict, and Salty resolves it the same way everywhere: the edit
    /// wins. A row agreed at 100 and edited to 200 while another device deleted it must come back WITH
    /// the edit, not be destroyed — the same principle as the tombstone push dropping a tombstone whose
    /// server copy was edited, seen from the other side.
    @Test func aRowEditedSinceTheAgreementIsUploadedEvenThoughTheServerDeletedIt() {
        let plan = tracked(local: [agreed("edited", 200, synced: 100)], server: [], lastSyncDate: date(1_000_000))
        #expect(plan.toUpload == ["edited"])
        #expect(plan.toDeleteLocally.isEmpty)
    }

    /// Any difference counts as an edit, including a stamp somehow LATER than the row — a clock that
    /// ran backwards must err toward upload, the non-destructive direction.
    @Test func aStampThatDisagreesInEitherDirectionReadsAsEdited() {
        #expect(tracked(local: [agreed("back", 50, synced: 100)], server: [], lastSyncDate: nil).toUpload == ["back"])
    }

    /// No clock is consulted for this decision any more, so the answer must not move when the watermark
    /// does — including when there is none, and when the clocks disagree wildly.
    @Test func theOutcomeDoesNotDependOnTheWatermark() {
        for watermark: Date? in [nil, date(0), date(50), date(100), date(999_999_999)] {
            #expect(tracked(local: [e("new", 100)], server: [], lastSyncDate: watermark).toUpload == ["new"])
            #expect(tracked(local: [agreed("old", 100)], server: [], lastSyncDate: watermark).toDeleteLocally == ["old"])
        }
    }

    /// Rows on both sides are unaffected: newest-wins is genuine conflict resolution, not an inference,
    /// and this change deliberately leaves it alone.
    @Test func rowsOnBothSidesStillResolveByNewestWins() {
        let plan = tracked(
            local: [agreed("local-newer", 200, synced: 100), agreed("server-newer", 100)],
            server: [e("local-newer", 100), e("server-newer", 200)],
            lastSyncDate: date(150)
        )
        #expect(plan.toUpload == ["local-newer"])
        #expect(plan.toDownload == ["server-newer"])
        #expect(plan.toDeleteLocally.isEmpty)
    }

    /// A first sync still uploads everything: there is no watermark to have disagreed with, and
    /// deletion inference is off entirely.
    @Test func aFirstSyncIsUnaffected() {
        let plan = RecipeSyncReconciler.plan(
            local: [agreed("a", 100), e("b", 100)], server: [],
            isFirstSync: true, lastSyncDate: nil, tracksAgreement: true
        )
        #expect(Set(plan.toUpload) == ["a", "b"])
        #expect(plan.toDeleteLocally.isEmpty)
    }

    /// A library that has not yet run SHARED-V0005 keeps the old rule exactly, since every entry then
    /// carries a nil stamp and the caller passes tracksAgreement: false.
    @Test func aLibraryWithoutTheColumnKeepsTheOldRule() {
        #expect(RecipeSyncReconciler.plan(local: [e("old", 50)], server: [],
                                          isFirstSync: false, lastSyncDate: date(150)).toDeleteLocally == ["old"])
        #expect(RecipeSyncReconciler.plan(local: [e("new", 200)], server: [],
                                          isFirstSync: false, lastSyncDate: date(150)).toUpload == ["new"])
    }
}
