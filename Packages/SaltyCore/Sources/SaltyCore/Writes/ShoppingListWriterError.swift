//
//  ShoppingListWriterError.swift
//  SaltyCore
//
//  Why a shopping-list write in `Writes/` refused, in words a caller can show.
//

import Foundation

public enum ShoppingListWriterError: Error, LocalizedError, Equatable {
    /// An insert was asked to use an id the library already holds. The table's primary key is declared
    /// `ON CONFLICT REPLACE`, so without this check the existing list would be silently overwritten.
    case idAlreadyInUse(String)
    /// A guarded update (`ShoppingListWriter.update(expecting:)`) found the stored row stamped
    /// differently from the copy the caller edited: something else -- a sync download, another
    /// window -- wrote the list in between, and the caller's edit was built on the old contents.
    case modifiedElsewhere(String)

    public var errorDescription: String? {
        switch self {
        case .idAlreadyInUse(let id): "A shopping list with the id \(id) already exists."
        case .modifiedElsewhere(let id): "The shopping list \(id) was changed elsewhere since it was loaded."
        }
    }
}
