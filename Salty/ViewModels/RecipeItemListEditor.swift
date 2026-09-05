//
//  RecipeItemListEditor.swift
//  Salty
//
//  The add / insert / delete / reorder half of the recipe's five editable lists -- ingredients,
//  directions, notes, preparation times, variations -- lifted out of the views so it can be tested.
//  Each editor previously kept a private copy of its list, mirrored it back into the recipe through a
//  pair of onChange handlers guarded by an equality check, and did its own index arithmetic in the
//  drop handler. Working on `inout` arrays instead lets the views bind straight to
//  `recipe.ingredients` and friends, so the mirror is gone.
//
//  Everything here is addressed by id rather than index, for the same reason
//  LibraryClassifiersEditViewModel is: indices go stale the moment the list changes underneath them.
//

import Foundation
import SwiftUI
import SaltyCore

enum RecipeItemListEditor {

    /// Where a dragged row will land.
    ///
    /// Held by id, not by index: the old editors tracked the drop indicator as an index and had to
    /// shift it by hand whenever a row was deleted. An id that has left the list simply matches
    /// nothing and draws nothing.
    enum DropTarget: Equatable, Sendable {
        /// Insert immediately above this row.
        case above(String)
        /// Insert after the last row.
        case end
    }

    // MARK: - Inserting

    /// Inserts `item` directly below `id`, or at the end if that row is no longer in the list.
    /// Returns the new row's id so the caller can scroll to and focus it.
    @discardableResult
    static func insert<Item: RecipeEditableRow>(
        _ item: Item,
        below id: String,
        in items: inout [Item]
    ) -> String {
        if let index = items.firstIndex(where: { $0.id == id }) {
            items.insert(item, at: index + 1)
        } else {
            items.append(item)
        }
        return item.id
    }

    /// Appends `item` and returns its id.
    @discardableResult
    static func append<Item: RecipeEditableRow>(_ item: Item, to items: inout [Item]) -> String {
        items.append(item)
        return item.id
    }

    // MARK: - Deleting

    /// Removes the row if it is still present. Returns whether anything was removed.
    @discardableResult
    static func delete<Item: RecipeEditableRow>(id: String, from items: inout [Item]) -> Bool {
        guard let index = items.firstIndex(where: { $0.id == id }) else { return false }
        items.remove(at: index)
        return true
    }

    // MARK: - Reordering

    /// Moves the row with `id` to `target`.
    ///
    /// Returns false, leaving the list untouched, whenever the drop makes no sense: an id that isn't
    /// in this list (a stray text drag, or a row dragged over from the other editor), a target row
    /// that has since been deleted, or a move that wouldn't change the order. That check is what
    /// makes dragging safe now that the payload is an id -- an unrecognised string is just refused.
    @discardableResult
    static func move<Item: RecipeEditableRow>(
        id: String,
        to target: DropTarget,
        in items: inout [Item]
    ) -> Bool {
        guard let source = items.firstIndex(where: { $0.id == id }) else { return false }

        let destination: Int
        switch target {
        case .above(let targetID):
            guard let index = items.firstIndex(where: { $0.id == targetID }) else { return false }
            destination = index
        case .end:
            destination = items.count
        }

        // `move(fromOffsets:toOffset:)` inserts before `toOffset` as measured in the array *before*
        // the move, so a row asked to land on either side of where it already is stays put.
        guard destination != source, destination != source + 1 else { return false }

        items.move(fromOffsets: IndexSet(integer: source), toOffset: destination)
        return true
    }

    /// Moves the row with `id` one position towards the top. Returns false if it is already there or
    /// isn't in the list, which is also what disables the corresponding menu item.
    @discardableResult
    static func moveUp<Item: RecipeEditableRow>(id: String, in items: inout [Item]) -> Bool {
        guard let index = items.firstIndex(where: { $0.id == id }), index > 0 else { return false }
        items.move(fromOffsets: IndexSet(integer: index), toOffset: index - 1)
        return true
    }

    /// Moves the row with `id` one position towards the bottom.
    @discardableResult
    static func moveDown<Item: RecipeEditableRow>(id: String, in items: inout [Item]) -> Bool {
        guard let index = items.firstIndex(where: { $0.id == id }), index < items.count - 1 else { return false }
        // Two past the source, because `toOffset` is measured before the row is lifted out.
        items.move(fromOffsets: IndexSet(integer: index), toOffset: index + 2)
        return true
    }

    // MARK: - Row bindings

    /// A binding to the row with `id` that resolves its position on every read and write.
    ///
    /// `ForEach($rows)` would be shorter, but the bindings it produces index by position, and a row
    /// outlives its own deletion: `withAnimation` keeps it on screen for the removal animation, and
    /// the last row's index is `count` by then. Deleting the last row of a list -- which is always
    /// what a just-added row is -- trapped on that. Resolving by id instead means a deleted row
    /// falls back to the value it was last drawn with and then disappears.
    static func binding<Item: RecipeEditableRow>(
        for id: String,
        in items: Binding<[Item]>,
        fallback: Item
    ) -> Binding<Item> {
        Binding(
            get: { items.wrappedValue.first { $0.id == id } ?? fallback },
            set: { newValue in
                // A write aimed at a row that is already gone is dropped rather than landing on
                // whichever row moved into its place.
                guard let index = items.wrappedValue.firstIndex(where: { $0.id == id }) else { return }
                items.wrappedValue[index] = newValue
            }
        )
    }

    // MARK: - Display

    /// The step number shown beside a direction, or nil for a heading. Headings don't take a number,
    /// so the count only walks the real steps ahead of this one.
    static func stepNumber(forDirectionWith id: String, in directions: [Direction]) -> Int? {
        guard let index = directions.firstIndex(where: { $0.id == id }),
              !directions[index].isHeadingRow else { return nil }
        return directions.prefix(index).count { !$0.isHeadingRow } + 1
    }

    /// Whether a row gets the tinted background of the striped-list effect. Short lists stay plain,
    /// where stripes read as noise rather than as rows.
    static func isAlternateRow<Item: RecipeEditableRow>(id: String, in items: [Item]) -> Bool {
        guard items.count >= 3, let index = items.firstIndex(where: { $0.id == id }) else { return false }
        return !index.isMultiple(of: 2)
    }
}
