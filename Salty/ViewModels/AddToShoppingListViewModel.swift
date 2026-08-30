//
//  AddToShoppingListViewModel.swift
//  Salty
//
//  Backs the "Add to Shopping List" sheet: which lines are on offer, which the chosen list already
//  covers, and the write itself. The reduction rules all live in `RecipeToShoppingList`; this is the
//  stateful shell around them.
//

import Foundation
import OSLog
import SQLiteData
import UUIDV7
import SaltyCore

@Observable
@MainActor
final class AddToShoppingListViewModel {
    private let logger = Logger(subsystem: "Salty", category: "Database")

    @ObservationIgnored
    @Dependency(\.defaultDatabase)
    private var database

    @ObservationIgnored
    @FetchAll(#sql("SELECT \(ShoppingList.columns) FROM \(ShoppingList.self) ORDER BY \(ShoppingList.name) COLLATE NOCASE"))
    var shoppingLists: [ShoppingList]

    /// Remembers the destination between visits -- the common case is a run of recipes going onto
    /// the same list, and re-picking it every time gets old fast.
    private static let lastUsedListKey = "lastUsedShoppingListId"

    /// One recipe ingredient group, as the picker shows it.
    struct CandidateGroup: Identifiable {
        let id: String
        let heading: String?
        let items: [RecipeToShoppingList.CandidateItem]
    }

    let recipeName: String
    let candidates: [RecipeToShoppingList.CandidateItem]
    /// Set when the recipe was being viewed at a scale other than 1, so the sheet can say the
    /// amounts it is about to add are the scaled ones.
    let scaleLabel: String?

    var selectedListId: String?
    var selectedItemIds: Set<String> = []
    /// Candidates the destination list already covers. Unchecked by default and labelled, rather
    /// than hidden -- silently dropping a line the user asked for is worse than a visible skip.
    var alreadyOnListIds: Set<String> = []
    var isSaving = false
    var operationError: String?

    init(recipe: Recipe, scaleFactor: Double, scaleLabel: String? = nil) {
        self.recipeName = recipe.name.trimmingCharacters(in: .whitespacesAndNewlines)
        self.candidates = RecipeToShoppingList.candidates(from: recipe, scaleFactor: scaleFactor)
        self.scaleLabel = scaleLabel
    }

    // MARK: - Derived state

    /// Candidates split into the recipe's own ingredient groups, in recipe order. Groups are display
    /// only: every selected line lands under the recipe's heading, not its ingredient heading.
    var groups: [CandidateGroup] {
        var groups: [CandidateGroup] = []
        for candidate in candidates {
            if let last = groups.last, last.heading == candidate.groupHeading {
                groups[groups.count - 1] = CandidateGroup(
                    id: last.id, heading: last.heading, items: last.items + [candidate]
                )
            } else {
                groups.append(CandidateGroup(
                    id: candidate.id, heading: candidate.groupHeading, items: [candidate]
                ))
            }
        }
        return groups
    }

    var selectedList: ShoppingList? {
        guard let selectedListId else { return nil }
        return shoppingLists.first { $0.id == selectedListId }
    }

    var selectedCount: Int { selectedItemIds.count }
    var canSave: Bool { selectedListId != nil && !selectedItemIds.isEmpty && !isSaving }
    var isEverythingSelected: Bool { selectedItemIds.count == candidates.count }

    var skippedSummary: String? {
        guard !alreadyOnListIds.isEmpty else { return nil }
        return alreadyOnListIds.count == 1
            ? "1 ingredient was already on this list."
            : "\(alreadyOnListIds.count) ingredients were already on this list."
    }

    func isSelected(_ candidate: RecipeToShoppingList.CandidateItem) -> Bool {
        selectedItemIds.contains(candidate.id)
    }

    func isAlreadyOnList(_ candidate: RecipeToShoppingList.CandidateItem) -> Bool {
        alreadyOnListIds.contains(candidate.id)
    }

    /// How many things a list currently has to buy, shown beside its name so a shelf of similar
    /// list names ("Costco", "Weekly") can be told apart at the point of choosing.
    func itemCount(of list: ShoppingList) -> Int {
        existingItems(of: list).count { !($0.isHeading ?? false) }
    }

    // MARK: - Selection

    /// Picks the destination the sheet opens on: the last one used, else the first list. Called once
    /// the fetched lists are available.
    func prepareInitialSelection() {
        guard selectedListId == nil else { return }
        let remembered = UserDefaults.standard.string(forKey: Self.lastUsedListKey)
        selectedListId = shoppingLists.first { $0.id == remembered }?.id ?? shoppingLists.first?.id
        refreshDuplicates()
    }

    /// Re-derives which candidates the destination already covers, and resets the checkmarks to
    /// "everything the list doesn't already have". Run whenever the destination changes: the answer
    /// is a property of the pairing, so a selection carried over from another list would be wrong.
    func refreshDuplicates() {
        guard let list = selectedList else {
            alreadyOnListIds = []
            selectedItemIds = Set(candidates.map(\.id))
            return
        }

        let existing = existingItems(of: list)
        alreadyOnListIds = Set(
            candidates
                .filter { RecipeToShoppingList.isAlreadyOnList($0.text, existingItems: existing) }
                .map(\.id)
        )
        selectedItemIds = Set(candidates.map(\.id)).subtracting(alreadyOnListIds)
    }

    func toggle(_ candidate: RecipeToShoppingList.CandidateItem) {
        if selectedItemIds.contains(candidate.id) {
            selectedItemIds.remove(candidate.id)
        } else {
            selectedItemIds.insert(candidate.id)
        }
    }

    /// Select-all / select-none, including the already-on-list rows: the detection is a default, not
    /// a rule, so "select all" has to be able to override it.
    func toggleSelectAll() {
        selectedItemIds = isEverythingSelected ? [] : Set(candidates.map(\.id))
    }

    // MARK: - Writing

    /// Creates an empty checklist and makes it the destination.
    ///
    /// An empty or whitespace-only name falls back to a generated one, so dismissing the naming
    /// dialog with nothing typed still produces a usable, distinctly named list rather than a blank
    /// row in the sidebar.
    func createList(named name: String) async {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let newList = ShoppingList(
            id: UUIDV7().uuidString,
            name: trimmed.isEmpty ? Self.availableNewListName(among: shoppingLists) : trimmed,
            isFreeform: false,
            lastModifiedDate: Date()
        )
        do {
            try await database.write { db in
                try ShoppingList.insert { newList }.execute(db)
            }
            selectedListId = newList.id
            refreshDuplicates()
        } catch {
            logger.error("Error creating shopping list for recipe add: \(error)")
            operationError = "The list couldn't be created."
        }
    }

    /// Appends the checked lines to the destination. Returns true when the sheet should close.
    ///
    /// The list row is re-read inside the write transaction rather than reused from `shoppingLists`,
    /// so a list edited elsewhere since the sheet opened keeps those edits: this only ever adds to
    /// whatever is stored at the moment of the write.
    func save() async -> Bool {
        guard let listId = selectedListId else { return false }
        let chosen = candidates.filter { selectedItemIds.contains($0.id) }
        guard !chosen.isEmpty else { return false }

        isSaving = true
        defer { isSaving = false }

        let heading = recipeName.isEmpty ? nil : recipeName
        do {
            try await database.write { db in
                guard var list = try ShoppingList.where({ $0.id.eq(listId) }).fetchOne(db) else { return }
                if list.isFreeform {
                    // Freeform lists round-trip through the checklist form, so the same insertion
                    // rules apply to both kinds without a second implementation.
                    let existing = ShoppingListFreeformConverter.items(from: list.contentsForFreeform ?? "")
                    let updated = RecipeToShoppingList.adding(chosen, to: existing, underHeading: heading)
                    list.contentsForFreeform = ShoppingListFreeformConverter.text(from: updated)
                } else {
                    list.contentsForList = RecipeToShoppingList.adding(
                        chosen, to: list.contentsForList, underHeading: heading
                    )
                }
                list.lastModifiedDate = Date()
                try ShoppingList.update(list).execute(db)
            }
        } catch {
            logger.error("Error adding recipe ingredients to shopping list \(listId): \(error)")
            operationError = "The ingredients couldn't be added."
            return false
        }

        UserDefaults.standard.set(listId, forKey: Self.lastUsedListKey)
        ShoppingListChangeNotifier.shared.noteExternalChange(listId: listId)
        return true
    }

    /// "New List", or "New List 2" and so on when that name is taken. Two identically named rows in
    /// the destination menu can't be told apart, and this is now the only way to make a list from
    /// here, so the names have to stay distinct on their own.
    static func availableNewListName(among lists: [ShoppingList], base: String = "New List") -> String {
        let taken = Set(lists.map { $0.name.trimmingCharacters(in: .whitespaces).lowercased() })
        guard taken.contains(base.lowercased()) else { return base }
        var suffix = 2
        while taken.contains("\(base) \(suffix)".lowercased()) { suffix += 1 }
        return "\(base) \(suffix)"
    }

    /// A list's items whichever way it stores them.
    private func existingItems(of list: ShoppingList) -> [ShoppingListListContents] {
        list.isFreeform
            ? ShoppingListFreeformConverter.items(from: list.contentsForFreeform ?? "")
            : list.contentsForList
    }
}
