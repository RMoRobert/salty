//
//  ImportFileSizeTests.swift
//  SaltyTests
//
//  Covers the size-capped file read used by the import flows (Data.contents(of:maxBytes:)), which guards
//  against loading an accidentally- or maliciously-huge PDF/image entirely into memory. Pure filesystem
//  test against temporary files.
//

import Testing
import Foundation
@testable import Salty

struct ImportFileSizeTests {

    private func makeTempFile(bytes: Int) throws -> URL {
        let url = URL.temporaryDirectory.appending(component: "salty-import-test-\(UUID().uuidString).bin")
        try Data(repeating: 0x41, count: bytes).write(to: url)
        return url
    }

    @Test func readsFileWithinLimit() throws {
        let url = try makeTempFile(bytes: 1024)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(Data.contents(of: url, maxBytes: 4096)?.count == 1024)
    }

    @Test func readsFileExactlyAtLimit() throws {
        let url = try makeTempFile(bytes: 2048)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(Data.contents(of: url, maxBytes: 2048)?.count == 2048)
    }

    @Test func rejectsFileOverLimit() throws {
        let url = try makeTempFile(bytes: 4096)
        defer { try? FileManager.default.removeItem(at: url) }
        #expect(Data.contents(of: url, maxBytes: 1024) == nil)
    }

    @Test func returnsNilForMissingFile() {
        let url = URL.temporaryDirectory.appending(component: "salty-missing-\(UUID().uuidString).bin")
        #expect(Data.contents(of: url, maxBytes: 1024) == nil)
    }
}
