//
//  SyncForgetOutcome.swift
//  SaltyCore
//

/// What `ServerSyncEngine.signOut()` managed to do, so the UI can say something useful when it fell short.
public enum SyncForgetOutcome: Sendable, Equatable {
    /// The token is dead server-side as well as gone from here.
    case revokedOnServer
    /// The server couldn't be told, so the token may still be live there. Forgetting still
    /// happened locally -- refusing to sign out because the network is down would be worse.
    case localOnly
}
