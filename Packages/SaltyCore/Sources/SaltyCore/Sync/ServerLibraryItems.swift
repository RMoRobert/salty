//
//  ServerLibraryItems.swift
//  SaltyCore
//
//  Wire shapes for the three name-only library tables. Deliberately dumb: the server sends a name and
//  a timestamp, and the reconciler in SaltySyncService decides what to do with them.
//

import Foundation

public struct ServerCourse: Codable, Sendable {
    public var id: String
    public var name: String?
    public var lastModifiedDate: Date?
}

public struct ServerCategory: Codable, Sendable {
    public var id: String
    public var name: String?
    public var lastModifiedDate: Date?
}

public struct ServerTag: Codable, Sendable {
    public var id: String
    public var name: String?
    public var lastModifiedDate: Date?
}
