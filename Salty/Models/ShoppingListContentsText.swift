//
//  ShoppingListContentsText.swift
//  Salty
//
//  The Apple app's wording for a shopping list's row subtitle. SaltyCore counts; this says it.
//

import Foundation
import SaltyCore

extension ShoppingList {
    /// "3 items", "1 line", "No items", "Empty".
    var contentsSummary: String {
        switch contentsCount {
        case .lines(0): String(localized: "Empty")
        case .lines(let count): String(inflected: "^[\(count) line](inflect: true)")
        case .items(0): String(localized: "No items")
        case .items(let count): String(inflected: "^[\(count) item](inflect: true)")
        }
    }
}
