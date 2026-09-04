//
//  URLSessionByteLimit.swift
//  SaltyCore
//
//  A size-capped fetch, for bodies that come from somewhere the app doesn't control.
//
//  `URLSession.data(for:)` buffers the whole body before it returns, so checking `data.count`
//  afterwards protects disk and the database but not memory: a chunked response that advertises no
//  Content-Length streams for as long as the sender likes. The fetch below reads the body through
//  `bytes(for:)` instead and gives up the moment the running total passes the cap, so the most it can
//  ever hold is the cap plus one byte.
//

import Foundation

/// Thrown by `URLSession.data(for:maxBytes:)` when a response body is over the caller's cap.
public struct ResponseTooLargeError: Error, Sendable, Equatable {
    /// The cap the caller set, in bytes.
    public let limit: Int
    /// How much was known when the fetch stopped: the advertised Content-Length when the server
    /// declared one up front, otherwise the bytes received before the limit tripped.
    public let observed: Int

    public init(limit: Int, observed: Int) {
        self.limit = limit
        self.observed = observed
    }
}

public extension URLSession {
    /// Fetches `request`, refusing to hold more than `maxBytes` of response body in memory.
    ///
    /// A server that announces its size is refused before a byte is read; one that doesn't is cut off
    /// as soon as the body passes the cap. Either way the failure is `ResponseTooLargeError`, so callers
    /// can tell "too big" apart from "unreachable".
    func data(for request: URLRequest, maxBytes: Int) async throws -> (Data, URLResponse) {
        let (bytes, response) = try await self.bytes(for: request)

        // -1 (`NSURLResponseUnknownLength`) when the server sent no Content-Length; only enforce a
        // declared size, and read the rest under the running check below.
        let expected = response.expectedContentLength
        if expected > Int64(maxBytes) {
            throw ResponseTooLargeError(limit: maxBytes, observed: Int(clamping: expected))
        }

        var data = Data()
        if expected > 0 {
            data.reserveCapacity(Int(clamping: expected))
        }
        for try await byte in bytes {
            data.append(byte)
            if data.count > maxBytes {
                throw ResponseTooLargeError(limit: maxBytes, observed: data.count)
            }
        }
        return (data, response)
    }
}
