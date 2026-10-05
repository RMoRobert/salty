//
//  ShoppingListStamp.swift
//  SaltyCore
//
//  The `lastModifiedDate` a shopping list carried when an editor loaded it, for
//  `ShoppingListWriter.update(id:in:now:expecting:_:)`.
//
//  Its own type rather than a bare `Date?` because "this row has never been stamped" (nil: a list
//  predating SHARED-V0002 that nothing has edited since) is itself a state an editor can have
//  loaded and must be able to expect -- which a `Date?` parameter would conflate with "don't check".
//

import Foundation

public struct ShoppingListStamp: Hashable, Sendable {
    public let lastModifiedDate: Date?

    /// Equal at the database's millisecond resolution. A stamp that has been through JSON (the C# app
    /// holds one between its reads and writes) can come back on an adjacent `Double` for the same
    /// millisecond, and an exact comparison would read that as someone else's edit.
    public static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.lastModifiedDate?.roundedToWireMillis == rhs.lastModifiedDate?.roundedToWireMillis
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(lastModifiedDate?.roundedToWireMillis)
    }

    public init(lastModifiedDate: Date?) {
        self.lastModifiedDate = lastModifiedDate
    }

    /// The stamp `list` carries.
    public init(of list: ShoppingList) {
        self.lastModifiedDate = list.lastModifiedDate
    }
}
