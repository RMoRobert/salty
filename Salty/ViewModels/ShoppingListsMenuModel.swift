//
//  ShoppingListsMenuModel.swift
//  Salty
//
//  The shopping lists, as the menu bar sees them.
//

import Foundation
import SQLiteData
import SaltyCore

/// Backs File ▸ Open Shopping List in New Window, which lists every shopping list by name.
///
/// `Commands` can't reach the main window's view model (it belongs to a scene, and the menu bar
/// outlives any one of them), so the menu keeps its own fetch. The table holds a handful of rows and
/// `@FetchAll` keeps them current, so a list created or renamed in one window shows up correctly in
/// the menu without anything having to push it there.
@Observable
@MainActor
final class ShoppingListsMenuModel {
    @ObservationIgnored
    @FetchAll(#sql("SELECT \(ShoppingList.columns) FROM \(ShoppingList.self) ORDER BY \(ShoppingList.name) COLLATE NOCASE"))
    var shoppingLists: [ShoppingList]
}
