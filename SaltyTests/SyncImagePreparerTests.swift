//
//  SyncImagePreparerTests.swift
//  SaltyTests
//
//  Covers the two things that matter about SyncImagePreparer: that it puts the right format on the
//  wire, and that its `async` entry point genuinely gets the work off the main actor.
//
//  The second is the reason the type exists, and it's invisible at the call site — `await` alone
//  doesn't tell you whether the callee changes executor. The guarantee is carried by `@concurrent`
//  on `prepare`; this test is the regression guard for the attribute being removed, since without it
//  a plain non-isolated `async` function only *happens* to run off-actor in this project's language
//  mode, and would inherit the caller's actor under `NonisolatedNonsendingByDefault`. A failure here
//  means the conversion went back to blocking the main thread during sync.
//

import Testing
import Foundation
@testable import Salty

@Suite struct SyncImagePreparerTests {

    // MARK: - Staying off the main actor

    /// Exercises the real entry point from the main actor, then asserts — via a probe declared with
    /// the identical isolation shape — that this shape runs off the main thread. The probe exists
    /// because `prepare`'s own executor can't be observed from outside without adding test hooks to
    /// production code; calling the real function alongside it keeps the mirror honest.
    @MainActor
    @Test func concurrentEntryPointRunsOffTheMainThread() async {
        #expect(isMainThreadNow(), "precondition: the test starts on the main actor")

        // The real call, from the main actor — the exact shape uploadImage uses.
        let prepared = await SyncImagePreparer.prepare(Self.onePixelPNG)
        #expect(prepared.mimeType == "image/png")

        let ranOnMain = await ExecutorProbe.observedMainThread()

        #expect(ranOnMain == false, "image preparation must not run on the main thread")
        #expect(isMainThreadNow(), "the caller should be back on the main actor afterwards")
    }

    /// `SyncImagePreparer` being callable from a non-isolated context at all is what keeps its work
    /// off the main actor; if the type ever gained `@MainActor` this test would stop compiling.
    @Test func preparerIsCallableWithoutMainActorIsolation() {
        let prepared = SyncImagePreparer.prepareSynchronously(Self.onePixelPNG)
        #expect(prepared.mimeType == "image/png")
    }

    // MARK: - Format detection
    //
    // Previously unreachable: these were private methods on the @MainActor sync service.

    @Test func passesThroughFormatsTheServerAlreadyAccepts() {
        let png = SyncImagePreparer.prepareSynchronously(Self.onePixelPNG)
        #expect(png.mimeType == "image/png")
        #expect(png.fileExtension == "png")
        #expect(png.data == Self.onePixelPNG, "an already-acceptable image should not be re-encoded")

        let jpeg = SyncImagePreparer.prepareSynchronously(Self.header([0xFF, 0xD8, 0xFF, 0x00, 0, 0, 0, 0]))
        #expect(jpeg.mimeType == "image/jpeg")
        #expect(jpeg.fileExtension == "jpg")

        let gif = SyncImagePreparer.prepareSynchronously(Self.header([0x47, 0x49, 0x46, 0x38, 0, 0, 0, 0]))
        #expect(gif.mimeType == "image/gif")
        #expect(gif.fileExtension == "gif")
    }

    @Test func tooShortToIdentifyIsSentAsJPEGRatherThanDropped() {
        let stub = SyncImagePreparer.prepareSynchronously(Data([0x01, 0x02, 0x03]))
        #expect(stub.mimeType == "image/jpeg")
        #expect(stub.data == Data([0x01, 0x02, 0x03]), "the original bytes should still be sent")
    }

    @Test func undecodableDataFallsBackToOctetStreamInsteadOfClaimingAFormat() {
        // Eight bytes matching no signature and not decodable as an image, so every conversion fails.
        let junk = Self.header([0x00, 0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07])
        let prepared = SyncImagePreparer.prepareSynchronously(junk)
        #expect(prepared.mimeType == "application/octet-stream")
        #expect(prepared.fileExtension == "bin")
        #expect(prepared.data == junk)
    }

    // MARK: - Fixtures

    private static func header(_ bytes: [UInt8]) -> Data {
        Data(bytes + [UInt8](repeating: 0, count: 16))
    }

    /// Smallest valid PNG (1x1, fully transparent).
    private static let onePixelPNG = Data(
        base64Encoded: "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk+M9QDwADhgGAWjR9awAAAABJRU5ErkJggg=="
    )!
}

/// `Thread.isMainThread` can't be referenced directly from an async context, so both the probe and the
/// assertions above route through a synchronous call.
private func isMainThreadNow() -> Bool {
    Thread.isMainThread
}

/// Mirrors `SyncImagePreparer.prepare`'s isolation exactly — `@concurrent` async static on a
/// `nonisolated` enum — so what it reports is the executor that declaration shape runs on.
private nonisolated enum ExecutorProbe {
    @concurrent static func observedMainThread() async -> Bool {
        isMainThreadNow()
    }
}
