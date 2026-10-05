//
//  SyncError.swift
//  SaltyCore
//
//  How a sync fails, and the wording a user sees for it.
//

import Foundation
import GRDB
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// MARK: - Sync Errors

public enum SyncError: LocalizedError, Sendable {
    case serverNotConfigured
    case credentialsNotConfigured
    case authenticationFailed(String)
    case networkError(String)
    case uploadFailed(String)
    case downloadFailed(String)
    case parseError(String)
    /// The user stopped the sync. Normalized from `CancellationError`/`URLError.cancelled` by
    /// `ServerSyncEngine.sync()` so callers can tell "you cancelled" apart from "something went wrong".
    case cancelled
    /// A sync finished within `minimumSyncInterval`, so this one was skipped. Benign: every caller
    /// treats it as "already up to date", never as a failure (and it must not clear auto-sync's
    /// pending-changes state the way a real success does).
    case throttled
    /// This device holds no usable sync token, so the password is needed once to enrol it. Thrown
    /// both on a first sync and when a token has been revoked from the server's devices page or
    /// invalidated by a password change. User-initiated syncs answer it by prompting; auto-sync
    /// answers it by standing down, since there is nobody to ask.
    case enrolmentRequired
    /// The server authenticated the user but issued no device token, meaning it predates the scheme.
    case enrolmentUnsupported
    /// The credential store refused to keep this device's sync id, so it cannot register as one device.
    case deviceIdUnavailable

    public var errorDescription: String? {
        switch self {
        case .cancelled:
            return "Sync was cancelled."
        case .throttled:
            return "Sync skipped: already synced a moment ago."
        case .serverNotConfigured:
            return "Server URL is not configured. Please set it in Settings."
        case .credentialsNotConfigured:
            return "Sync is not set up on this device yet. Enter your username and password to connect it."
        case .enrolmentRequired:
            return "This device needs to be connected to the server again. Enter your username and password to reconnect it."
        case .enrolmentUnsupported:
            return "This server is too old to connect devices for sync. Please update Salty Server, then try again."
        case .deviceIdUnavailable:
            return "This device's sync identity couldn't be saved. Check that the keychain is available, then try again."
        case .authenticationFailed(let message):
            return "Authentication failed: \(message)"
        case .networkError(let message):
            return "Network error: \(message)"
        case .uploadFailed(let message):
            return "Upload failed: \(message)"
        case .downloadFailed(let message):
            return "Download failed: \(message)"
        case .parseError(let message):
            return "Parse error: \(message)"
        }
    }
}

extension SyncError {
    /// True when `error` means "this sync was cancelled" in any of the forms it can arrive in: a Swift task
    /// cancellation, the `URLError` URLSession raises for the request it aborted, or our own normalized
    /// `.cancelled`. Used to keep a deliberate cancel out of the error paths (no red banner in Settings, no
    /// auto-sync failure count).
    public static func isCancellation(_ error: Error) -> Bool {
        if error is CancellationError { return true }
        if let syncError = error as? SyncError, case .cancelled = syncError { return true }
        if let urlError = error as? URLError, urlError.code == .cancelled { return true }
        return false
    }

    /// User-facing message for a non-2xx HTTP response that never surfaces the raw response body, which
    /// could be HTML error page (proxy 502, captive portal, wrong address) that shouldn't be shown as raw text.
    /// If the body is small JSON carrying an `error`/`message`/`detail` field, that text is preferred.
    public static func httpMessage(status: Int, body: Data) -> String {
        if let serverMessage = serverJSONMessage(from: body) { return serverMessage }
        // An HTML body (not Salty Server JSON) means something else must have answered: a reverse proxy,
        // captive portal, etc. In particular, NGINX returns HTML 403 page (and actual 403 code) if access
        // list does not allow, so lead with that possibility since that is likely a common Salty Server setup:
        if bodyLooksLikeHTML(body) {
            return "Access to the server was forbidden (HTTP \(status)). A reverse proxy, firewall, portal (sever responded with HTML), or other issue may be blocking access. Verify your network connection, server setup, and try again."
        }
        switch status {
        case 401:
            return "The server rejected your username or password (HTTP 401)."
        case 403:
            return "Access to the server was forbidden (HTTP 403). Check firewall or IP restrictions, and verify your username and password."
        case 404:
            return "The server didn't recognize that request (HTTP 404). Check server address."
        case 408, 429:
            return "Error: HTTP \(status). Server may be busy. Try again in a moment."
        case 500...599:
            return "Error: HTTP \(status). Ensure server is functional and try again."
        default:
            return "The server returned an unexpected response (HTTP \(status))."
        }
    }

    /// True when the body is a JSON object, which is what Salty Server itself answers with. A reverse
    /// proxy or captive portal that intercepted the request answers with HTML (or nothing), so this is
    /// how a verdict *from the server* is told apart from a network in the way.
    public static func bodyIsServerJSON(_ data: Data) -> Bool {
        guard !data.isEmpty, !bodyLooksLikeHTML(data) else { return false }
        return (try? JSONSerialization.jsonObject(with: data)) is [String: Any]
    }

    /// True when the body looks like an HTML/markup page rather than our JSON API response. Our API always
    /// returns JSON (starts with `{` or `[`); a leading `<` means an HTML/XML page from a proxy/gateway.
    private static func bodyLooksLikeHTML(_ data: Data) -> Bool {
        guard !data.isEmpty,
              let prefix = String(data: data.prefix(512), encoding: .utf8)?
                  .trimmingCharacters(in: .whitespacesAndNewlines) else { return false }
        return prefix.hasPrefix("<")
    }

    /// Extracts a human message from a SMALL JSON error body. Returns nil for HTML / large / non-JSON bodies.
    private static func serverJSONMessage(from data: Data) -> String? {
        guard !data.isEmpty, data.count < 4096,
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        for key in ["message", "error", "detail"] {
            if let text = object[key] as? String, !text.isEmpty { return capped(text) }
        }
        return nil
    }

    /// The longest server-supplied message shown as-is. The server is trusted to be ours, but anything
    /// reachable at its address can answer, and a status line is no place for a stack trace.
    public static let maxServerMessageLength = 300

    /// `text` trimmed, collapsed to one line, and cut to `maxServerMessageLength` characters.
    static func capped(_ text: String) -> String {
        let oneLine = text.split(whereSeparator: \.isNewline).joined(separator: " ")
            .trimmingCharacters(in: .whitespaces)
        guard oneLine.count > maxServerMessageLength else { return oneLine }
        return String(oneLine.prefix(maxServerMessageLength)) + "…"
    }
}

/// Maps ANY error thrown during sync to a friendly, HTML-free string for display. Covers our own
/// `SyncError` (already friendly), connectivity failures (`URLError`), and unreadable responses
/// (`DecodingError`, e.g. an HTML page where JSON was expected).
public func friendlySyncMessage(_ error: Error) -> String {
    // Checked first: a cancelled request is a `URLError` whose default wording ("Couldn't reach the
    // server") would blame the network for something the user chose to do.
    if SyncError.isCancellation(error) {
        return "Sync was cancelled. (Anything already transferred was kept; sync again to finish the rest.)"
    }
    switch error {
    case let urlError as URLError:
        switch urlError.code {
        case .notConnectedToInternet, .networkConnectionLost:
            return "No internet connection. Connect to a network and try again."
        case .cannotFindHost, .cannotConnectToHost, .dnsLookupFailed, .timedOut, .secureConnectionFailed:
            return "Couldn't reach the server. It may be offline or only reachable on your home network. Check the server address in Settings."
        default:
            return "Couldn't reach the server (\(urlError.localizedDescription))"
        }
    case is DecodingError:
        return "The server returned a response the app couldn't read. Check that the address points to your Salty server."
    case let syncError as SyncError:
        return syncError.errorDescription ?? "Sync failed."
    case let databaseError as DatabaseError:
        // GRDB's description carries the SQL statement and its arguments, which are no use to a reader.
        return "Sync couldn't update the recipe library on this device (database error \(databaseError.resultCode.rawValue)). Try again; if it keeps happening, restart Salty."
    case is ResponseTooLargeError:
        return "The server sent more data than a sync accepts. Check that the address points to your Salty server."
    default:
        // Anything else is local (a file error, say) and its text can carry paths, so it is shown
        // only as far as the cap allows.
        return SyncError.capped(error.localizedDescription)
    }
}
