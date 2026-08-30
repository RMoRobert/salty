//
//  ContractCorpusTests.swift
//  SaltyTests
//
//  Runs the shared conformance corpus (`salty-contract/corpus`) against this client's implementation.
//  The SaltyKMP and Salty.NET cores run the same cases through their own runners.
//
//  This suite deliberately holds no expected values of its own — they all live in the corpus, so adding
//  a case there adds it to three clients at once. What lives here is only the mapping from a corpus
//  `op` to the SaltyCore function that implements it.
//
//  An unmapped `op` FAILS rather than skipping. Silently ignoring a case nobody wired up turns a new
//  rule into no coverage at all, which is the failure mode the corpus exists to prevent.
//

import Testing
import Foundation
import GRDB
import SaltyCore
import UUIDV7

@Suite("Contract corpus")
struct ContractCorpusTests {

    private static let platform = "swift"

    /// Loaded once, lazily. A load failure surfaces as an empty list, which `corpusIsReachable`
    /// turns into one clear failure rather than sixty confusing ones.
    static let allCases: [CorpusCase] = (try? CorpusLoader.load()) ?? []

    @Test("the corpus is reachable and non-empty")
    func corpusIsReachable() throws {
        #expect(!(try CorpusLoader.load()).isEmpty)
    }

    @Test("dates")      func dates()      throws { try runSuite("dates") }
    @Test("ids")        func ids()        throws { try runSuite("ids") }
    @Test("migrations") func migrations() throws { try runSuite("migrations") }
    @Test("reconciler") func reconciler() throws { try runSuite("reconciler") }

    /// One test per suite, looping its cases.
    ///
    /// Deliberately NOT `@Test(arguments:)`, which would give a node per case: parameterised discovery
    /// over this corpus made the test runner time out while preparing to run (six minutes, three runner
    /// processes, no tests executed). Looping costs the per-case nodes in Xcode and nothing else — the
    /// failure messages already name the case id, and it matches the KMP and .NET runners' shape.
    ///
    /// Failures are left to `#expect` inside `execute` rather than collected here, because `#expect`
    /// RECORDS an issue instead of throwing: a `do`/`catch` around it would see nothing, count the case
    /// as passed, and — worse — report every genuine waiver as a stale one.
    private func runSuite(_ suite: String) throws {
        let cases = Self.allCases.filter { $0.suite == suite }
        try #require(!cases.isEmpty, "no cases loaded for suite '\(suite)'")

        var waived = 0
        var notApplicable = 0

        for c in cases {
            // Not a waiver: the rule permits more than one implementation and Salty chose another.
            if let why = c.notApplicable[Self.platform] {
                notApplicable += 1
                print("N/A    \(c.id) — \(why)")
                continue
            }

            guard let why = c.knownDivergence[Self.platform] else {
                try execute(c)
                continue
            }

            // A waiver claims this client FAILS the case, and `withKnownIssue` verifies the claim for
            // free: it absorbs the recorded issue, and FAILS the run if the body records none — which is
            // exactly what should happen when a divergence is fixed and the entry goes stale.
            waived += 1
            print("WAIVED \(c.because)\n    reason: \(why)")
            withKnownIssue("\(c.id): \(why)") { try execute(c) }
        }

        print("\(suite): \(cases.count - waived - notApplicable) checked, "
            + "\(waived) waived, \(notApplicable) n/a")
    }

    private func execute(_ c: CorpusCase) throws {
        switch c.op {

        // ---- dates ---------------------------------------------------------------------------

        // `SyncWireDate.date(from:)` is Salty's only exposed timestamp parser, and its format list
        // names "GRDB default (space-separated)" explicitly, so it is the database reader too.
        // The result is normalised through `roundedToWireMillis` because that is the instant the
        // reconciler actually compares — see the note on DATE-007 in SPEC.md.
        case "parse_database":
            let parsed = SyncWireDate.date(from: c.input.stringValue ?? "")
            let actual = parsed.map { Int64(($0.roundedToWireMillis.timeIntervalSince1970 * 1000).rounded()) }
            #expect(actual == c.expect["epoch_ms"]?.int64Value, "\(c.because)")

        // Salty never formats a database timestamp itself — GRDB does, on the way into a DATETIME
        // column. So this asks GRDB what it actually stores, which is the thing the contract is about.
        case "format_database":
            let queue = try DatabaseQueue()
            let stored = try queue.write { db -> String? in
                try db.execute(sql: #"CREATE TABLE "t" ("d" DATETIME)"#)
                try db.execute(sql: #"INSERT INTO "t" ("d") VALUES (?)"#, arguments: [try instant(c)])
                return try String.fetchOne(db, sql: #"SELECT "d" FROM "t""#)
            }
            #expect(stored == c.expect.stringValue, "\(c.because)")

        case "format_wire":
            #expect(SyncWireDate.string(from: try instant(c)) == c.expect.stringValue, "\(c.because)")

        // Encoded through JSONEncoder rather than a formatter, because `.iso8601` is what
        // `.saltyRecipe` files are written with and its exact output is the thing DATE-003 pins.
        case "format_file":
            let encoder = JSONEncoder()
            encoder.dateEncodingStrategy = .iso8601
            let encoded = String(decoding: try encoder.encode([try instant(c)]), as: UTF8.self)
            let stripped = encoded.trimmingCharacters(in: CharacterSet(charactersIn: "[]\""))
            #expect(stripped == c.expect.stringValue, "\(c.because)")

        // Asked as "is rounding idempotent?" rather than "is the sub-millisecond remainder zero?".
        // A `Date` is a Double of seconds and cannot hold a whole millisecond exactly, so a remainder
        // test compares against a float epsilon that varies with the clock value — it passed on some
        // runs and failed on others. Re-rounding an already-rounded value returns the identical Double,
        // so this is exact, and it tests the property DATE-009 is actually about.
        case "now_precision":
            let now = Date().roundedToWireMillis
            #expect(now == now.roundedToWireMillis, "\(c.because)\n  carries sub-millisecond precision")

        // ---- ids -----------------------------------------------------------------------------

        case "new_id":
            let pattern = try Regex(c.expect["matches"]?.stringValue ?? "")
            for _ in 0..<Self.idSampleSize {
                let id = UUIDV7().uuidString
                #expect(id.wholeMatch(of: pattern) != nil, "\(c.because)\n  offending id: \(id)")
            }

        case "new_id_uniqueness":
            let size = c.expect["sample_size"]?.intValue ?? 0
            let ids = (0..<size).map { _ in UUIDV7().uuidString }
            #expect(Set(ids).count == size, "\(c.because)")

        case "normalize_id":
            #expect(SaltyId.normalize(c.input.stringValue ?? "") == c.expect.stringValue, "\(c.because)")

        // Minted, not derived (ID-005). The corpus asks the two things that remain true of an opaque
        // id: two calls for the same pair differ, and the result is an ordinary identifier.
        case "junction_id":
            let first = SaltyId.new()
            if c.expect["distinct"] != nil {
                #expect(SaltyId.new() != first, "\(c.because)")
            }
            if let pattern = c.expect["matches"]?.stringValue {
                #expect(try first.wholeMatch(of: Regex(pattern)) != nil,
                        "\(c.because)\n  offending id: \(first)")
            }

        // ---- migrations ----------------------------------------------------------------------

        // Read off the real migrator rather than a parallel list, so this cannot drift from what is
        // actually registered — the one place Salty has a better handle on this than the other two.
        case "grdb_migration_identifiers":
            #expect(saltyMigrator().migrations == c.expect.arrayValue.compactMap(\.stringValue), "\(c.because)")

        case "shared_migration_identifiers":
            #expect(saltySharedMigrations.map(\.id) == c.expect.arrayValue.compactMap(\.stringValue), "\(c.because)")

        case "shared_migration_effects":
            try assertMigrationEffects(c)

        // ---- reconciler ----------------------------------------------------------------------

        case "reconcile":
            try assertReconcile(c)

        case "deletion_guard":
            assertDeletionGuard(c)

        default:
            Issue.record("""
                Unmapped corpus op '\(c.op)' in \(c.id).
                  Map it to a SaltyCore function here, or remove the case from the corpus.
                """)
        }
    }

    /// Applies each shared migration to a database that predates it and checks the column it claims to
    /// add really arrives, with the declared type.
    ///
    /// The tables are created bare rather than through `saltyMigrator()`, because a fully migrated
    /// database already has every column — running the migrations against one would only exercise their
    /// existence guards and would pass even if a migration did nothing at all.
    private func assertMigrationEffects(_ c: CorpusCase) throws {
        // Collected rather than asserted one at a time: a case covering five migrations would otherwise
        // report only the first mismatch and hide the rest behind it.
        var mismatches: [String] = []

        for effect in c.expect.arrayValue {
            let id = effect["id"]?.stringValue ?? ""
            guard let migration = saltySharedMigrations.first(where: { $0.id == id }) else {
                mismatches.append("no shared migration is declared with id '\(id)'")
                continue
            }
            let columns = effect["adds_columns"]?.arrayValue ?? []

            let queue = try DatabaseQueue()
            try queue.write { db in
                for table in Set(columns.compactMap { $0["table"]?.stringValue }) {
                    try db.execute(sql: #"CREATE TABLE "\#(table)" ("id" TEXT PRIMARY KEY NOT NULL)"#)
                }

                try migration.apply(db)

                for column in columns {
                    let table = column["table"]?.stringValue ?? ""
                    let name = column["column"]?.stringValue ?? ""
                    let type = column["type"]?.stringValue ?? ""
                    let actual = try String.fetchOne(
                        db,
                        sql: "SELECT type FROM pragma_table_info(?) WHERE name = ?",
                        arguments: [table, name]
                    )
                    if actual != type {
                        mismatches.append("\(id) must add \(table).\(name) as \(type), but it is \(actual ?? "absent")")
                    }
                }
            }
        }

        #expect(mismatches.isEmpty, "\(c.because)\n  \(mismatches.joined(separator: "\n  "))")
    }

    /// SYNC-016: whether deletions inferred from a side's absence may be applied at all.
    ///
    /// The predicate only. That a client consults it on BOTH directions of EVERY collection is wiring
    /// rather than a value, so it cannot be seen from here and each client pins it with its own tests.
    /// What this stops is the three drifting on the rule itself — which is what happened when the local
    /// half existed and the server half did not.
    private func assertDeletionGuard(_ c: CorpusCase) {
        let allows = RecipeSyncReconciler.allowsDeletions(
            sideCount: Int(c.input["side_count"]?.int64Value ?? 0),
            pendingDeletions: Int(c.input["pending_deletions"]?.int64Value ?? 0)
        )
        let expected = c.expect["allows"].map { if case .bool(let b) = $0 { return b } else { return false } } ?? false

        #expect(allows == expected, "\(c.because)")
    }

    private func assertReconcile(_ c: CorpusCase) throws {
        func entries(_ key: String, withAgreement: Bool) -> [RecipeSyncReconciler.Entry] {
            (c.input[key]?.arrayValue ?? []).map { raw in
                RecipeSyncReconciler.Entry(
                    id: raw["id"]?.stringValue ?? "",
                    lastModified: date(raw["last_modified_ms"]?.int64Value ?? 0),
                    syncedModified: withAgreement
                        ? raw["synced_modified_ms"]?.int64Value.map(date)
                        : nil
                )
            }
        }

        // NOTE: `local_changes_since_ms` has no counterpart here — RecipeSyncReconciler.plan takes no
        // such parameter (SPEC.md SYNC-011 / DIV-001). It is ignored rather than silently approximated,
        // which is what makes REC-040 fail and waive rather than pass by accident.
        let plan = RecipeSyncReconciler.plan(
            local: entries("local", withAgreement: true),
            server: entries("server", withAgreement: false),
            isFirstSync: c.input["is_first_sync"].map { if case .bool(let b) = $0 { return b } else { return false } } ?? false,
            lastSyncDate: c.input["last_sync_ms"]?.int64Value.map(date),
            tracksAgreement: c.input["tracks_agreement"].map { if case .bool(let b) = $0 { return b } else { return false } } ?? false
        )

        // Sets, not sequences: no rule constrains the order ids come back in, and pinning an incidental
        // order would make a harmless refactor look like a regression.
        func expected(_ key: String) -> Set<String> {
            Set((c.expect[key]?.arrayValue ?? []).compactMap(\.stringValue))
        }
        #expect(Set(plan.toUpload) == expected("to_upload"), "\(c.because)\n  [toUpload]")
        #expect(Set(plan.toDownload) == expected("to_download"), "\(c.because)\n  [toDownload]")
        #expect(Set(plan.toDeleteLocally) == expected("to_delete_locally"), "\(c.because)\n  [toDeleteLocally]")
        #expect(Set(plan.toDeleteOnServer) == expected("to_delete_on_server"), "\(c.because)\n  [toDeleteOnServer]")
    }

    // ---- corpus value helpers ------------------------------------------------------------------

    private static let idSampleSize = 1000

    private func date(_ epochMillis: Int64) -> Date {
        Date(timeIntervalSince1970: Double(epochMillis) / 1000)
    }

    private func instant(_ c: CorpusCase) throws -> Date {
        guard let millis = c.input["epoch_ms"]?.int64Value else {
            throw CorpusError.message("\(c.id): input has no epoch_ms")
        }
        return date(millis)
    }
}
