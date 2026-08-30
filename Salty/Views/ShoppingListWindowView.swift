//
//  ShoppingListWindowView.swift
//  Salty
//
//  Root of the "shopping-list-window" scene: one shopping list, in a window of its own.
//

import SwiftUI
import SQLiteData
import SaltyCore

/// One shopping list in its own window, so it can sit *beside* a recipe rather than replacing it —
/// selecting Shopping Lists in the sidebar takes over the main window's content column, which is
/// exactly what you don't want while cooking from a recipe you're shopping for.
///
/// Routes to the same two editors the detail column uses (`ShoppingListDetailView` for a checklist,
/// `ShoppingListFreeformView` for a text list), so a list behaves identically wherever it's open.
/// Editors in different windows keep each other current through `ShoppingListChangeNotifier`.
struct ShoppingListWindowView: View {
    /// The window's value — the list's id. A binding because `WindowGroup(id:for:)` hands one over;
    /// this view only reads it.
    @Binding var listId: String?

    /// The whole (small) table rather than one row, because the window has to follow the row it
    /// shows: a rename retitles the window, and "Convert to Freeform Text" — which can be chosen in
    /// another window — swaps the editor underneath it. `@FetchAll` keeps both current for free.
    @FetchAll(#sql("SELECT \(ShoppingList.columns) FROM \(ShoppingList.self)"))
    private var shoppingLists: [ShoppingList]

    private var list: ShoppingList? {
        guard let listId else { return nil }
        return shoppingLists.first { $0.id == listId }
    }

    var body: some View {
        if let list {
            Group {
                if list.isFreeform {
                    ShoppingListFreeformView(listId: list.id)
                } else {
                    ShoppingListDetailView(listId: list.id)
                }
            }
            .id(list.id)
            .navigationTitle(list.name)
            #if os(macOS)
            .navigationSubtitle(list.isFreeform ? "Freeform List" : "Checklist")
            #endif
        } else {
            // The list was deleted while its window was open, or the window was restored pointing at
            // one that's since gone.
            ContentUnavailableView("No Shopping List", systemImage: "checklist")
                .navigationTitle("Shopping List")
        }
    }
}

#Preview {
    NavigationStack {
        ShoppingListWindowView(listId: .constant("shopping-list-2-id"))
    }
}
