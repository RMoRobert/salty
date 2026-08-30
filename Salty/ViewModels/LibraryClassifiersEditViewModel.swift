//
//  LibraryClassifiersEditViewModel.swift
//  Salty
//
//  Backs LibraryClassifiersEditView for whichever classifier it was created with -- one view model
//  instead of the three near-identical ones this replaces (categories, courses, and tags differ only
//  in which table they live in, which LibraryClassifier already captures).
//
//  Rows are addressed by id throughout. The previous editors tracked selection as indices into the
//  live query results, which drifted whenever the list changed underneath them: selecting the row
//  "after" a delete, and, on create, selecting `count - 1` -- an index that was both stale (the fetch
//  hadn't refreshed yet) and wrong (the list is name-sorted, so a new row is rarely last).
//

import Foundation
import OSLog
import SQLiteData
import SwiftUI
import SaltyCore

@MainActor
@Observable
final class LibraryClassifiersEditViewModel {
    private let logger = Logger(subsystem: "Salty", category: "Library")

    @ObservationIgnored
    @Dependency(\.defaultDatabase) private var database

    /// Which of the three the editor is showing. Fixed for the lifetime of the view.
    let classifier: LibraryClassifier

    // MARK: - View state

    var searchText = ""
    /// Sort state, as column + direction: the macOS table headers can flip either column either way,
    /// while the iOS menu sets only the two pairings in `LibraryClassifierSortOrder`. Both bind to
    /// these two properties (`tableSortOrder` / `sortOrder` below).
    var sortColumn: LibraryClassifierSortColumn = .name
    var sortAscending = true
    /// Selected row ids.
    var selection: Set<String> = []
    /// The row being renamed inline, or `newRowID` while the "new row" field is showing.
    private(set) var editingID: String?
    var editingName = ""
    /// Set while the name being edited collides with another row; drives the inline merge prompt
    /// rather than the dead-end "already exists" alert the old editors showed.
    private(set) var nameConflict: LibraryClassifierEditor.NameConflict?
    /// Rows the delete confirmation is about. Kept separate from `isConfirmingDeletion` on purpose:
    /// SwiftUI flips the presentation binding back to false *before* running the dialog button's
    /// action, so driving presentation off this array directly would empty it before the delete ran.
    private(set) var pendingDeletion: [LibraryClassifierItem] = []
    var isConfirmingDeletion = false
    /// Rows a pending merge would fold together, survivor included, in survivor order. Held while the
    /// merge sheet is up; the sheet is the only place the survivor can be chosen.
    private(set) var mergeCandidates: [LibraryClassifierItem] = []
    /// Which of `mergeCandidates` survives -- and so whose name and id remain. Bound by the sheet's
    /// picker, seeded with the same choice the duplicate scan would make.
    var mergeSurvivorID: String?
    var isConfirmingMerge = false
    /// Row to bring into view, and when. `.afterReload` waits for the next items refresh -- after a
    /// create, rename, or merge the write hasn't reached the observed query yet, so scrolling
    /// immediately would target a row the list doesn't hold and silently do nothing. `.now` is for
    /// pointing at a row that already exists (revealing a name conflict), where no refresh is coming.
    enum ScrollTarget: Equatable {
        case now(id: String)
        case afterReload(id: String)
    }
    var scrollTarget: ScrollTarget?
    /// Set when a create/rename/delete/merge fails; surfaced via `.errorAlert`.
    var operationError: String?

    /// Guards against committing the same edit twice -- `onSubmit` and the focus-loss handler both
    /// fire when the user presses Return, and a double commit would create two rows.
    private var isCommitting = false

    @ObservationIgnored
    @FetchAll var items: [LibraryClassifierItem]

    /// Sentinel id for the inline "new row" field. Not a real row, so it is never selectable.
    static let newRowID = "new-classifier-row"

    init(classifier: LibraryClassifier) {
        self.classifier = classifier
    }

    // MARK: - Derived state

    var isCreating: Bool { editingID == Self.newRowID }
    var isEditing: Bool { editingID != nil }

    func isEditing(_ id: String) -> Bool { editingID == id }

    var canRename: Bool { selection.count == 1 && !isEditing }
    var canDelete: Bool { !selection.isEmpty && !isEditing }
    /// Merging needs something to merge *into*, so one row isn't enough.
    var canMerge: Bool { selection.count > 1 && !isEditing }

    var isSearching: Bool { !searchText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// Everything the list query depends on, for the view's `.task(id:)`.
    var queryKey: String { "\(sortColumn.rawValue)|\(sortAscending)|\(searchText)" }

    /// The iOS sort menu's view of the sort state. The getter collapses combinations the menu
    /// doesn't offer (only reachable on macOS) onto its nearest option; the menu is iOS-only, so in
    /// practice it only ever reads back what it set.
    var sortOrder: LibraryClassifierSortOrder {
        get { sortColumn == .recipeCount && !sortAscending ? .mostUsed : .name }
        set {
            sortColumn = newValue.column
            sortAscending = newValue.ascending
        }
    }

    /// The macOS table's view of the same state, as the header-click comparators `Table` binds to.
    /// Only the first comparator is meaningful -- the query's tie-break is fixed (name, ascending).
    var tableSortOrder: [KeyPathComparator<LibraryClassifierItem>] {
        get {
            switch sortColumn {
            case .name:
                return [KeyPathComparator(\.name, order: sortAscending ? .forward : .reverse)]
            case .recipeCount:
                return [KeyPathComparator(\.recipeCount, order: sortAscending ? .forward : .reverse)]
            }
        }
        set {
            guard let first = newValue.first else { return }
            sortColumn = first.keyPath == \LibraryClassifierItem.recipeCount ? .recipeCount : .name
            sortAscending = first.order == .forward
        }
    }

    var deletionTitle: String { Self.deletionTitle(for: pendingDeletion, classifier: classifier) }

    var deletionMessage: String { Self.deletionMessage(for: pendingDeletion, classifier: classifier) }

    /// Title for the delete confirmation, naming the single row where there is one.
    static func deletionTitle(for rows: [LibraryClassifierItem], classifier: LibraryClassifier) -> String {
        if rows.count == 1, let only = rows.first {
            return "Delete “\(only.name)”?"
        }
        return "Delete \(rows.count) \(rows.count == 1 ? classifier.singularLabel : classifier.pluralLabel)?"
    }

    /// What the delete costs, in recipes. Recipes are never deleted -- they only lose the classification,
    /// which is the part worth saying out loud before a category disappears from thirty of them.
    ///
    /// An unused row still gets a confirmation, just a shorter one: a delete that asks only sometimes
    /// is a delete you stop reading, and swipe-to-delete is easy to trigger by accident.
    static func deletionMessage(for rows: [LibraryClassifierItem], classifier: LibraryClassifier) -> String {
        let affected = rows.reduce(0) { $0 + $1.recipeCount }
        guard affected > 0 else {
            return "This cannot be undone."
        }
        // One recipe can hold two of the categories/tags being deleted, so a multi-row total is an
        // upper bound. A recipe has only one course, so that total is exact.
        let mayDoubleCount = rows.count > 1 && classifier != .course
        let count = affected == 1 ? "1 recipe" : "\(affected) recipes"
        let recipes = mayDoubleCount ? "up to \(count)" : count

        switch classifier {
        case .course:
            let remain = affected == 1
                ? "That recipe will remain, but its course selection will be removed."
                : "Those recipes will remain, but their course selection will be removed."
            return "\(recipes) \(affected == 1 ? "is" : "are") currently classified with this course. \(remain) This cannot be undone."
        case .category, .tag:
            if rows.count == 1 {
                let noun = classifier.singularLabel.lowercased()
                return "This \(noun) is being used by \(recipes). Removing it will remove it from those recipes, but the recipes will remain. This cannot be undone."
            }
            let noun = classifier.pluralLabel.lowercased()
            return "These \(noun) are being used by \(recipes). Removing them will remove them from those recipes, but the recipes will remain. This cannot be undone."
        }
    }

    var mergeTitle: String { Self.mergeTitle(for: mergeCandidates, classifier: classifier) }

    var mergeMessage: String {
        Self.mergeMessage(for: mergeCandidates, survivorID: mergeSurvivorID, classifier: classifier)
    }

    /// Title for the merge sheet. Counts rather than names: the names are listed right below it.
    static func mergeTitle(for rows: [LibraryClassifierItem], classifier: LibraryClassifier) -> String {
        "Merge \(rows.count) \(rows.count == 1 ? classifier.singularLabel : classifier.pluralLabel)"
    }

    /// What the merge does, in the survivor's own name -- which is the whole reason the sheet exists,
    /// since the survivor's spelling is the one that remains.
    ///
    /// The rows being folded away are named while there are few enough to read, and counted after
    /// that; either way they are listed in full above this sentence, so the count loses nothing.
    static func mergeMessage(
        for rows: [LibraryClassifierItem],
        survivorID: String?,
        classifier: LibraryClassifier
    ) -> String {
        guard let survivor = rows.first(where: { $0.id == survivorID }) else {
            return "Choose which \(classifier.singularLabel.lowercased()) to keep."
        }
        let losing = rows.filter { $0.id != survivor.id }
        guard !losing.isEmpty else {
            return "Nothing to merge into “\(survivor.name)”."
        }

        // Named up to three, counted beyond that (so doesn't get longer than list!)
        let subject: String
        if losing.count <= 3 {
            subject = losing.map { "“\($0.name)”" }.formatted(.list(type: .and))
        } else {
            subject = "The other \(losing.count) \(classifier.pluralLabel.lowercased())"
        }
        let plural = losing.count == 1
        let verb = plural ? "will be deleted, and its recipes" : "will be deleted, and their recipes"
        let outcome = classifier == .course
            ? "will use “\(survivor.name)” instead"
            : "will be added to “\(survivor.name)”"

        return "\(subject) \(verb) \(outcome). The recipes themselves are not deleted. This cannot be undone."
    }

    // MARK: - Query

    /// Reloads the list for the current search text and sort order. Driven by the view's `.task(id:)`.
    func updateQuery() async {
        let trimmed = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        do {
            try await $items.load(
                LibraryClassifierQueryBuilder.statement(
                    classifier: classifier,
                    searchPattern: trimmed.isEmpty ? nil : "%\(trimmed)%",
                    column: sortColumn,
                    ascending: sortAscending
                )
            )
        } catch {
            // Reload failed; the list keeps its prior contents. Non-destructive, so log only.
            logger.error("Error loading \(self.classifier.rawValue) list: \(error)")
        }
    }

    // MARK: - Pointing at a row

    /// Points the UI at the row a create, rename, or merge just produced.
    ///
    /// On macOS that means selecting it: selection is how the table shows you where the row landed
    /// once the list re-sorts. On iOS the list draws selection outside Select mode too -- a flat gray
    /// band on a row nobody selected, which is the look this editor set out to avoid -- so there the
    /// scroll does the pointing, and the selection (whose ids a merge may just have deleted) is
    /// cleared instead.
    private func pointAtRow(_ id: String) {
        #if os(macOS)
        selection = [id]
        #else
        selection.removeAll()
        #endif
    }

    // MARK: - Inline editing

    /// Every entry point lands an edit already in progress first: starting a second one while the
    /// first is still open would drop whatever was typed into it without saying so.
    func beginCreating() async {
        await endEditing()
        editingID = Self.newRowID
        editingName = ""
        nameConflict = nil
    }

    func beginRenaming(id: String) async {
        await endEditing()
        guard let item = items.first(where: { $0.id == id }) else { return }
        editingID = id
        editingName = item.name
        nameConflict = nil
    }

    /// Starts renaming the selected row, for the toolbar button.
    func beginRenamingSelection() async {
        guard let id = selection.first, selection.count == 1 else { return }
        await beginRenaming(id: id)
    }

    /// Ends an in-place edit because the user moved on -- focus left the field, another row was
    /// selected, or the editor is closing.
    ///
    /// Moving on saves, the way it does in Finder. The exception is a name collision: that edit can't
    /// land as typed, and quietly merging or renaming behind the user's back is the wrong guess, so
    /// walking away abandons it.
    ///
    /// Selection changes have to be a trigger, not just focus: on iOS, tapping another row does *not*
    /// take focus from a text field inside a list row, so the row being renamed would otherwise stay
    /// editable while the selection moved elsewhere.
    func endEditing() async {
        guard editingID != nil else { return }
        if nameConflict != nil {
            cancelEditing()
        } else {
            await commitEditing()
        }
    }

    func cancelEditing() {
        editingID = nil
        editingName = ""
        nameConflict = nil
    }

    /// Commits the inline field: creates a row, renames one, or -- on an empty name -- just backs out,
    /// which is also how an accidental "new row" disappears.
    func commitEditing() async {
        guard !isCommitting, let editingID else { return }
        isCommitting = true
        defer { isCommitting = false }

        let name = editingName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else {
            cancelEditing()
            return
        }
        if editingID == Self.newRowID {
            await create(named: name)
        } else {
            await rename(id: editingID, to: name)
        }
    }

    private func create(named name: String) async {
        let classifier = classifier
        do {
            if let conflict = try await database.read({ db in
                try LibraryClassifierEditor.existingRow(classifier: classifier, name: name, in: db)
            }) {
                nameConflict = conflict
                return
            }
            let newID = try await database.write { db in
                try LibraryClassifierEditor.create(classifier: classifier, name: name, in: db)
            }
            cancelEditing()
            pointAtRow(newID)
            scrollTarget = .afterReload(id: newID)
        } catch {
            logger.error("Error creating \(classifier.rawValue): \(error)")
            operationError = "Couldn’t create the \(classifier.singularLabel.lowercased()). \(error.localizedDescription)"
        }
    }

    private func rename(id: String, to name: String) async {
        let classifier = classifier
        guard let current = items.first(where: { $0.id == id }) else {
            cancelEditing()
            return
        }
        guard current.name != name else {
            cancelEditing()
            return
        }
        do {
            if let conflict = try await database.read({ db in
                try LibraryClassifierEditor.existingRow(classifier: classifier, name: name, excludingId: id, in: db)
            }) {
                nameConflict = conflict
                return
            }
            try await database.write { db in
                try LibraryClassifierEditor.rename(classifier: classifier, id: id, to: name, in: db)
            }
            cancelEditing()
            scrollTarget = .afterReload(id: id)
        } catch {
            logger.error("Error renaming \(classifier.rawValue): \(error)")
            operationError = "Couldn’t rename the \(classifier.singularLabel.lowercased()). \(error.localizedDescription)"
        }
    }

    // MARK: - Name conflicts

    /// Folds the row being renamed into the one that already holds the name, which is what a rename
    /// onto an existing name usually means ("Deserts" → "Desserts"). The existing row survives, so its
    /// spelling is the one that remains, and its recipes gain the ones from the row that goes away.
    func mergeIntoConflictingRow() async {
        guard let conflict = nameConflict,
              let editingID,
              editingID != Self.newRowID,
              let losing = items.first(where: { $0.id == editingID })
        else { return }

        let classifier = classifier
        let group = LibraryDuplicateGroup(
            kind: classifier,
            survivor: LibraryClassifierItem(id: conflict.id, name: conflict.name, recipeCount: 0),
            duplicates: [losing]
        )
        do {
            _ = try await database.write { db in
                try LibraryDuplicateMerger.merge([group], in: db)
            }
            cancelEditing()
            pointAtRow(conflict.id)
            scrollTarget = .afterReload(id: conflict.id)
        } catch {
            logger.error("Error merging \(classifier.rawValue): \(error)")
            operationError = "Couldn’t merge the \(classifier.pluralLabel.lowercased()). \(error.localizedDescription)"
        }
    }

    /// Abandons the edit and points the user at the row that already has the name.
    func revealConflictingRow() {
        guard let conflict = nameConflict else { return }
        cancelEditing()
        pointAtRow(conflict.id)
        scrollTarget = .now(id: conflict.id)
    }

    // MARK: - Deleting

    func requestDeletion(ids: some Sequence<String>) {
        let ids = Set(ids)
        let rows = items.filter { ids.contains($0.id) }
        guard !rows.isEmpty else { return }
        pendingDeletion = rows
        isConfirmingDeletion = true
    }

    func cancelDeletion() {
        isConfirmingDeletion = false
        pendingDeletion = []
    }

    func confirmDeletion() async {
        isConfirmingDeletion = false
        let rows = pendingDeletion
        pendingDeletion = []
        guard !rows.isEmpty else { return }

        let classifier = classifier
        let ids = rows.map(\.id)
        do {
            _ = try await database.write { db in
                try LibraryClassifierEditor.delete(classifier: classifier, ids: ids, in: db)
            }
            selection.subtract(ids)
        } catch {
            logger.error("Error deleting \(classifier.rawValue): \(error)")
            operationError = "Couldn’t delete the \(rows.count == 1 ? classifier.singularLabel.lowercased() : classifier.pluralLabel.lowercased()). \(error.localizedDescription)"
        }
    }

    // MARK: - Merging

    /// Opens the merge sheet on the selected rows, pre-picking the survivor the duplicate scan would
    /// have chosen (most recipes, ties to the oldest row) -- so the common case is one tap, while the
    /// name that survives is still on screen to be changed.
    func requestMerge(ids: some Sequence<String>) {
        let ids = Set(ids)
        let rows = LibraryDuplicateFinder.ranked(items.filter { ids.contains($0.id) })
        // Two rows is the minimum: merging needs something to merge into.
        guard rows.count > 1 else { return }
        mergeCandidates = rows
        mergeSurvivorID = rows.first?.id
        isConfirmingMerge = true
    }

    func cancelMerge() {
        isConfirmingMerge = false
        mergeCandidates = []
        mergeSurvivorID = nil
    }

    /// Folds every candidate but the survivor into it, in one transaction. The survivor's recipes end
    /// up as the union of all of them; `LibraryDuplicateMerger` skips links a recipe already has, so a
    /// recipe filed under two of the merged rows isn't left listed twice.
    func confirmMerge() async {
        let rows = mergeCandidates
        guard let survivor = rows.first(where: { $0.id == mergeSurvivorID }) else { return }
        let duplicates = rows.filter { $0.id != survivor.id }
        guard !duplicates.isEmpty else {
            cancelMerge()
            return
        }
        cancelMerge()

        let classifier = classifier
        let group = LibraryDuplicateGroup(kind: classifier, survivor: survivor, duplicates: duplicates)
        do {
            _ = try await database.write { db in
                try LibraryDuplicateMerger.merge([group], in: db)
            }
            pointAtRow(survivor.id)
            scrollTarget = .afterReload(id: survivor.id)
        } catch {
            logger.error("Error merging \(classifier.rawValue): \(error)")
            operationError = "Couldn’t merge the \(classifier.pluralLabel.lowercased()). \(error.localizedDescription)"
        }
    }
}
