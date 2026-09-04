//
//  ResponseByteLimitTests.swift
//  SaltyTests
//
//  `URLSession.data(for:maxBytes:)`, the size-capped fetch behind web import and sync image
//  downloads. The interesting case is a body with no Content-Length: the old check ran after the
//  whole body had been buffered, so the cap protected disk but not memory.
//

import Testing
import Foundation
import SaltyCore

/// Answers every request with a fixed body. With `declareLength` off the response carries no
/// Content-Length, which is the chunked-transfer shape the streaming check exists for.
final class ByteLimitStubURLProtocol: URLProtocol {
    nonisolated(unsafe) static var body = Data()
    nonisolated(unsafe) static var declareLength = false

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }
    override func stopLoading() {}

    override func startLoading() {
        let url = request.url ?? URL(string: "https://stub.local")!
        var headers: [String: String] = [:]
        if Self.declareLength { headers["Content-Length"] = String(Self.body.count) }
        let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: nil, headerFields: headers)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        // Delivered in small pieces, as a real transfer would be.
        var offset = 0
        while offset < Self.body.count {
            let end = min(offset + 16, Self.body.count)
            client?.urlProtocol(self, didLoad: Self.body[offset..<end])
            offset = end
        }
        client?.urlProtocolDidFinishLoading(self)
    }
}

@Suite(.serialized)
struct ResponseByteLimitTests {

    private func makeSession(body: Data, declareLength: Bool) -> URLSession {
        ByteLimitStubURLProtocol.body = body
        ByteLimitStubURLProtocol.declareLength = declareLength
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ByteLimitStubURLProtocol.self]
        return URLSession(configuration: config)
    }

    private let request = URLRequest(url: URL(string: "https://stub.local/big")!)

    @Test func aBodyWithinTheCapIsReturnedWhole() async throws {
        let body = Data((0..<100).map { UInt8($0) })
        let session = makeSession(body: body, declareLength: false)
        let (data, _) = try await session.data(for: request, maxBytes: 200)
        #expect(data == body)
    }

    @Test func aBodyExactlyAtTheCapIsAllowed() async throws {
        let body = Data(repeating: 7, count: 64)
        let session = makeSession(body: body, declareLength: false)
        let (data, _) = try await session.data(for: request, maxBytes: 64)
        #expect(data.count == 64)
    }

    /// The case that matters: no Content-Length, so only the running check can stop it.
    @Test func anUndeclaredOversizedBodyIsCutOffAtTheCap() async {
        let session = makeSession(body: Data(repeating: 1, count: 1000), declareLength: false)
        await #expect(throws: ResponseTooLargeError.self) {
            _ = try await session.data(for: request, maxBytes: 100)
        }
    }

    @Test func aDeclaredOversizedBodyIsRefusedUpFront() async {
        let session = makeSession(body: Data(repeating: 1, count: 1000), declareLength: true)
        do {
            _ = try await session.data(for: request, maxBytes: 100)
            Issue.record("expected the declared length to be refused")
        } catch let error as ResponseTooLargeError {
            #expect(error.limit == 100)
            #expect(error.observed == 1000, "a declared size is reported as observed without reading the body")
        } catch {
            Issue.record("unexpected error \(error)")
        }
    }
}
