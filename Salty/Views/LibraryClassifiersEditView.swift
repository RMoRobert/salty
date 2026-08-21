//
//  LibraryClassifiersEditView.swift
//  Salty
//
//  The category / course / tag editor -- one view for all three, parameterized by LibraryClassifier,
//  replacing LibraryCategoriesEditView / LibraryCoursesEditView / LibraryTagsEditView. Still opened as
//  three separate windows on macOS and three sheets on iOS; only the implementation is shared.
//
//  Renaming and creating happen in place, the way Finder renames a tag and Reminders adds a list --
//  the old editors put both behind an alert with a text field in it. A name that collides with an
//  existing row offers a merge rather than refusing the edit, since "Deserts" → "Desserts" almost
//  always means "these are the same thing".
//
//  macOS shows a real `Table`: labeled Name / Recipes column headers that sort on click, replacing
//  the sort menu iOS keeps (a `Table` collapses to one unlabeled column on iPhone, so the List stays
//  the right shape there). Renames still happen in the Name cell; the new-row field docks at the
//  bottom, since a phantom row inside a `Table` would fight row selection.
//
//  iOS keeps no persistent selection, the way Reminders treats its list of lists: tapping a row
//  starts the rename, swiping offers Delete and Rename, and a long press offers both. Selection
//  appears only in the explicit Select mode (from the ⋯ menu, as in Notes and Photos), where rows
//  grow checkmark circles and the bar offers a bulk Delete. The flat-gray look that prompted this
//  design is what `List(selection:)` shows outside edit mode on iPhone -- so outside Select mode,
//  nothing binds selection at all.
//

import SwiftUI
import SaltyCore

struct LibraryClassifiersEditView: View {
    @State private var viewModel: LibraryClassifiersEditViewModel
    @Environment(\.dismiss) private var dismiss
    @FocusState private var nameFieldFocused: Bool
    #if !os(macOS)
    /// Drives iOS Select mode (checkmark-circle multi-select) by hand rather than via `EditButton`,
    /// so entry can live in the ⋯ menu and exit in the bar's own Done -- and so the sheet-dismissing
    /// Done can hide while the mode is active instead of sitting next to a second, different Done.
    @State private var editMode: EditMode = .inactive

    private var isSelecting: Bool { editMode.isEditing }
    #endif

    init(classifier: LibraryClassifier) {
        _viewModel = State(initialValue: LibraryClassifiersEditViewModel(classifier: classifier))
    }

    private var classifier: LibraryClassifier { viewModel.classifier }

    var body: some View {
        classifierContent
            .navigationTitle("Edit \(classifier.pluralLabel)")
            #if !os(macOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .searchable(text: $viewModel.searchText)
            .toolbar { toolbarContent }
            // An alert, not a confirmation dialog: this one carries consequences to read (how many
            // recipes lose the classification), and an alert keeps Cancel on screen. A confirmation
            // dialog anchors as a popover when it comes from a toolbar button or a row, and the
            // system drops the cancel button there -- tapping outside is the only way back.
            .alert(
                viewModel.deletionTitle,
                isPresented: $viewModel.isConfirmingDeletion
            ) {
                Button("Delete", role: .destructive) {
                    Task { await viewModel.confirmDeletion() }
                }
                Button("Cancel", role: .cancel) {
                    viewModel.cancelDeletion()
                }
            } message: {
                Text(viewModel.deletionMessage)
            }
            // A sheet rather than an alert: this confirmation has a choice in it (which row survives),
            // and an alert can hold a text field but not a list.
            .sheet(isPresented: $viewModel.isConfirmingMerge) {
                LibraryClassifierMergeView(
                    classifier: classifier,
                    candidates: viewModel.mergeCandidates,
                    survivorID: $viewModel.mergeSurvivorID,
                    merge: { Task { await viewModel.confirmMerge() } },
                    cancel: { viewModel.cancelMerge() }
                )
            }
            .errorAlert($viewModel.operationError)
            .task(id: viewModel.queryKey) {
                await viewModel.updateQuery()
            }
            .overlay {
                if viewModel.items.isEmpty && !viewModel.isCreating {
                    emptyState
                }
            }
            .onChange(of: viewModel.editingID) { _, editingID in
                if editingID == nil {
                    nameFieldFocused = false
                }
            }
    }

    @ViewBuilder
    private var classifierContent: some View {
        #if os(macOS)
        classifierTable
        #else
        // ScrollViewReader rather than ScrollPosition for the same reason as the recipe list:
        // `ScrollPosition.scrollTo(id:)` only reaches views registered via `.scrollTargetLayout()`,
        // which a `List` has no way to apply, so it silently does nothing -- the proxy is the only
        // way to scroll a `List` to a specific row.
        ScrollViewReader { proxy in
            classifierListCore(proxy: proxy)
        }
        .environment(\.editMode, $editMode)
        #endif
    }

    #if os(macOS)
    // MARK: - Table (macOS)

    private var classifierTable: some View {
        Table(viewModel.items, selection: $viewModel.selection, sortOrder: $viewModel.tableSortOrder) {
            TableColumn("Name", value: \.name) { item in
                if viewModel.isEditing(item.id) {
                    nameField(prompt: classifier.singularLabel, conflictAction: .merge)
                } else {
                    Text(item.name)
                }
            }
            TableColumn("Recipes", value: \.recipeCount) { item in
                Text(item.recipeCount, format: .number)
                    .monospacedDigit()
                    .foregroundStyle(.secondary)
                    .accessibilityLabel(item.recipeCount == 1 ? "1 recipe" : "\(item.recipeCount) recipes")
            }
            .width(min: 55, ideal: 70, max: 90)
            .alignment(.numeric)
        }
        .alternatingRowBackgrounds()
        .contextMenu(forSelectionType: String.self) { ids in
            rowMenu(for: ids)
        } primaryAction: { ids in
            // Double-click renames, matching Finder and the sidebar lists in Mail.
            if ids.count == 1, let id = ids.first {
                Task { await viewModel.beginRenaming(id: id) }
            }
        }
        .onDeleteCommand {
            guard viewModel.canDelete else { return }
            viewModel.requestDeletion(ids: viewModel.selection)
        }
        .onChange(of: viewModel.selection) { _, _ in
            // Clicking another row lands the edit -- focus loss alone doesn't always fire when the
            // click goes to a different table row.
            Task { await viewModel.endEditing() }
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            if viewModel.isCreating {
                newRowBar
            }
        }
        .onChange(of: viewModel.scrollTarget) { _, target in
            // `Table` has no programmatic scrolling (no ScrollViewReader, no ScrollPosition), so on
            // macOS the target is consumed without acting on it; the created row is still selected.
            if target != nil {
                viewModel.scrollTarget = nil
            }
        }
    }

    /// The new-row field, docked under the table while a row is being added. Return commits, Esc
    /// cancels, and clicking away commits -- the same rules as the in-cell rename.
    private var newRowBar: some View {
        VStack(spacing: 0) {
            Divider()
            nameField(prompt: "New \(classifier.singularLabel)", conflictAction: .reveal)
                .padding(10)
        }
        .background(.bar)
    }
    #else
    // MARK: - List (iOS)

    private func classifierListCore(proxy: ScrollViewProxy) -> some View {
        // The selection binding matters only in Select mode; outside it the rows are Buttons, which
        // swallow taps before the list's selection machinery sees them.
        List(selection: $viewModel.selection) {
            ForEach(viewModel.items) { item in
                if viewModel.isEditing(item.id) {
                    nameField(prompt: classifier.singularLabel, conflictAction: .merge)
                } else if isSelecting {
                    // Plain content in Select mode, so taps toggle the checkmark instead of firing
                    // a rename.
                    LibraryClassifierRowView(item: item)
                } else {
                    // Tap renames, in place -- the row's one job in an editor. beginRenaming lands
                    // any edit already open first, so tapping row to row commits as it goes.
                    Button {
                        Task { await viewModel.beginRenaming(id: item.id) }
                    } label: {
                        LibraryClassifierRowView(item: item)
                    }
                    .foregroundStyle(.primary)
                    // Destructive first, so it sits at the edge and takes the full swipe -- the shape
                    // Mail and Reminders use for multi-action swipes.
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            viewModel.requestDeletion(ids: [item.id])
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        Button("Rename", systemImage: "pencil") {
                            Task { await viewModel.beginRenaming(id: item.id) }
                        }
                        .tint(.accentColor)
                    }
                    .contextMenu {
                        Button("Rename", systemImage: "pencil") {
                            Task { await viewModel.beginRenaming(id: item.id) }
                        }
                        Button(role: .destructive) {
                            viewModel.requestDeletion(ids: [item.id])
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                    }
                    .id(item.id)
                }
            }
            if viewModel.isCreating {
                nameField(prompt: "New \(classifier.singularLabel)", conflictAction: .reveal)
                    .id(LibraryClassifiersEditViewModel.newRowID)
            }
        }
        // A new row is typed at the bottom but lands wherever its name sorts, and a rename can move a
        // row clear across the list. Animating the difference is what connects the two -- otherwise the
        // row you just typed vanishes from under the cursor and an identical one blinks into existence
        // somewhere else. `items` is the whole projection, so this covers inserts, moves, and deletes.
        .animation(.default, value: viewModel.items)
        .listStyle(.plain)
        // Dragging dismisses the keyboard right away, as Reminders does. While the keyboard is up
        // the list carries a keyboard-height bottom inset, so a fling mid-rename could sail a whole
        // screen past the last row and race the commit that fires on focus loss.
        .scrollDismissesKeyboard(.immediately)
        .onChange(of: viewModel.editingID) { _, editingID in
            if editingID == LibraryClassifiersEditViewModel.newRowID {
                // The new-row field lives at the bottom of the list, which in a long list is off
                // screen -- and a row the lazy list hasn't built can't take focus, so the field must
                // be scrolled into existence first. It grabs focus itself in onAppear.
                Task { await scrollToRow(LibraryClassifiersEditViewModel.newRowID, anchor: .bottom, proxy: proxy) }
            }
        }
        .onChange(of: viewModel.scrollTarget) { _, target in
            guard case .now(let id) = target else { return }
            viewModel.scrollTarget = nil
            Task { await scrollToRow(id, anchor: .center, proxy: proxy) }
        }
        .onChange(of: viewModel.items) { _, items in
            // A create/rename/merge sets its target before the observed query delivers the changed
            // row, so the scroll waits here for the refresh. The first refresh consumes the target
            // whether or not the row made it -- under an active search the new row may legitimately
            // not match the filter, and a stale target must not fire on some later reload.
            guard case .afterReload(let id) = viewModel.scrollTarget else { return }
            viewModel.scrollTarget = nil
            guard items.contains(where: { $0.id == id }) else { return }
            Task { await scrollToRow(id, anchor: .center, proxy: proxy) }
        }
    }

    /// Scrolls to a row, then re-issues the scroll a couple of times -- the same catch-up the recipe
    /// list needs: a row inserted by the current update (the new-row field, a just-created row) isn't
    /// registered with the proxy on the first try, and one scroll can fall short near the end of a
    /// long list while rows are still being built.
    private func scrollToRow(_ id: String, anchor: UnitPoint, proxy: ScrollViewProxy) async {
        withAnimation(.easeOut(duration: 0.2)) {
            proxy.scrollTo(id, anchor: anchor)
        }
        for _ in 0..<2 {
            try? await Task.sleep(for: .milliseconds(250))
            proxy.scrollTo(id, anchor: anchor)
        }
    }
    #endif

    /// The inline rename / create field, plus the merge prompt when the name is already taken.
    private func nameField(prompt: String, conflictAction: ClassifierNameFieldView.ConflictAction) -> some View {
        ClassifierNameFieldView(
            prompt: prompt,
            name: $viewModel.editingName,
            isFocused: $nameFieldFocused,
            conflict: viewModel.nameConflict,
            conflictAction: conflictAction,
            classifier: classifier,
            commit: { Task { await viewModel.commitEditing() } },
            endEditing: { Task { await viewModel.endEditing() } },
            cancel: { viewModel.cancelEditing() },
            resolveConflict: {
                switch conflictAction {
                case .merge: Task { await viewModel.mergeIntoConflictingRow() }
                case .reveal: viewModel.revealConflictingRow()
                }
            }
        )
    }

    @ViewBuilder
    private func rowMenu(for ids: Set<String>) -> some View {
        if ids.count == 1, let id = ids.first {
            Button("Rename", systemImage: "pencil") {
                Task { await viewModel.beginRenaming(id: id) }
            }
        }
        if ids.count > 1 {
            Button("Merge…", systemImage: "arrow.triangle.merge") {
                viewModel.requestMerge(ids: ids)
            }
        }
        if ids.isEmpty {
            Button("New \(classifier.singularLabel)", systemImage: "plus") {
                Task { await viewModel.beginCreating() }
            }
        } else {
            Button(role: .destructive) {
                viewModel.requestDeletion(ids: ids)
            } label: {
                Label(ids.count == 1 ? "Delete" : "Delete \(ids.count) \(classifier.pluralLabel)", systemImage: "trash")
            }
        }
    }

    private var emptyState: some View {
        Group {
            if viewModel.isSearching {
                ContentUnavailableView.search(text: viewModel.searchText)
            } else {
                ContentUnavailableView {
                    Label("No \(classifier.pluralLabel)", systemImage: classifier.systemImage)
                } description: {
                    Text(emptyStateDescription)
                } actions: {
                    Button("New \(classifier.singularLabel)", systemImage: "plus") {
                        Task { await viewModel.beginCreating() }
                    }
                }
            }
        }
    }

    private var emptyStateDescription: String {
        switch classifier {
        case .category:
            return "Create categories like “Pasta” or “Holiday” to help you organize recipes (recipes can belong to more than one category)."
        case .course:
            return "Create courses like “Main Dish” or “Dessert” to help you organize recipes (recipes can belong to only one course)."
        case .tag:
            return "Create tags like “quick” or “high fiber” as another way to help you organize recipes (recipes can have any number of tags)."
        }
    }

    // MARK: - Toolbar

    @ToolbarContentBuilder
    private var toolbarContent: some ToolbarContent {
        #if os(macOS)
        // No sort item here: the table's column headers are the sort control.
        //
        // Fixed spacers split the liquid-glass toolbar into separate pods -- without them macOS 26
        // fuses adjacent items into one capsule, lumping destructive Delete against Rename and New.
        // This is the system apps' own arrangement (Mail separates its destructive actions the same
        // way). Pre-26 macOS never fused buttons, so the spacers are simply skipped there.
        ToolbarItem(placement: .automatic) {
            Button(role: .destructive) {
                viewModel.requestDeletion(ids: viewModel.selection)
            } label: {
                Label("Delete", systemImage: "trash")
            }
            .disabled(!viewModel.canDelete)
            .help("Delete")
        }
        if #available(macOS 26.0, *) {
            ToolbarSpacer(.fixed, placement: .automatic)
        }
        // Rename and New share a pod; only Delete stands apart. All three are icon-only, the macOS
        // toolbar default -- the Label titles still read out in VoiceOver, and .help puts them in
        // hover tooltips.
        ToolbarItemGroup(placement: .primaryAction) {
            Button("Rename", systemImage: "pencil") {
                Task { await viewModel.beginRenamingSelection() }
            }
            .disabled(!viewModel.canRename)
            .help("Rename")

            Button("Merge", systemImage: "arrow.triangle.merge") {
                viewModel.requestMerge(ids: viewModel.selection)
            }
            .disabled(!viewModel.canMerge)
            .help("Merge")

            Button("New \(classifier.singularLabel)", systemImage: "plus") {
                Task { await viewModel.beginCreating() }
            }
            .help("New \(classifier.singularLabel)")
        }
        #else
        // The bar belongs to whichever mode is active, the way iOS hands a whole bar to a sub-mode
        // instead of dimming what no longer applies -- and so "Done" only ever means one thing at a
        // time: exit Select mode while selecting, commit while renaming, close the sheet otherwise.
        if isSelecting {
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    withAnimation {
                        editMode = .inactive
                    }
                    viewModel.selection.removeAll()
                }
            }
            ToolbarItemGroup(placement: .bottomBar) {
                Button(role: .destructive) {
                    viewModel.requestDeletion(ids: viewModel.selection)
                } label: {
                    Label(
                        viewModel.selection.count > 1 ? "Delete \(viewModel.selection.count)" : "Delete",
                        systemImage: "trash"
                    )
                }
                .disabled(viewModel.selection.isEmpty)
                Spacer()
                // Only reachable at two or more selected, which is also where Select mode teaches
                // that merging exists at all -- there is no selection to merge outside it.
                Button("Merge", systemImage: "arrow.triangle.merge") {
                    viewModel.requestMerge(ids: viewModel.selection)
                }
                .disabled(!viewModel.canMerge)
                .labelStyle(.titleAndIcon)
            }
        } else if viewModel.isEditing {
            // The rename/create sub-mode: an explicit cancel, which iOS otherwise lacks -- macOS
            // has Esc for this.
            ToolbarItemGroup(placement: .bottomBar) {
                Button("Cancel", role: .cancel) {
                    viewModel.cancelEditing()
                }
                Spacer()
                Button("Done") {
                    Task { await viewModel.commitEditing() }
                }
            }
        } else {
            // Rename and delete live on the rows themselves (tap, swipe, long press), so the bar
            // holds only what has no row: creating.
            ToolbarItemGroup(placement: .bottomBar) {
                Spacer()

                Button("New", systemImage: "plus") {
                    Task { await viewModel.beginCreating() }
                }
                .labelStyle(.titleAndIcon)
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Done") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .topBarLeading) {
                moreMenu
            }
        }
        #endif
    }

    #if !os(macOS)
    /// The ⋯ menu: Select mode plus the sort picker, the arrangement Notes and Photos use -- which
    /// also retires the bespoke sort icon in favor of the standard More button.
    private var moreMenu: some View {
        Menu {
            Button("Select", systemImage: "checkmark.circle") {
                Task {
                    // Land any open rename first; Select mode assumes no edit is in flight.
                    await viewModel.endEditing()
                    withAnimation {
                        editMode = .active
                    }
                }
            }
            // A submenu picker rather than inline options under a heading: iOS renders neither a
            // Section header nor an inline picker's label inside a menu (both collapse to a bare
            // divider), while the menu-style picker shows a labeled "Sort By" row carrying the
            // current choice -- the shape Photos and Files use for sorting in their ⋯ menus.
            Picker("Sort By", selection: $viewModel.sortOrder) {
                ForEach(LibraryClassifierSortOrder.allCases) { order in
                    Text(order.label).tag(order)
                }
            }
            .pickerStyle(.menu)
        } label: {
            // Toolbar buttons draw their own glass circle on iOS 26, so the pre-circled glyph would
            // nest a circle in a circle; the bare ellipsis is what the system apps show there.
            Label("More", systemImage: isLiquidGlassAvailable() ? "ellipsis" : "ellipsis.circle")
        }
    }
    #endif
}

// MARK: - Rows

/// One classifier, with the number of recipes using it -- the fastest way to spot the ones worth
/// merging away, and the count the delete confirmation warns about.
private struct LibraryClassifierRowView: View {
    let item: LibraryClassifierItem

    var body: some View {
        HStack {
            Text(item.name)
            Spacer(minLength: 12)
            Text(item.recipeCount, format: .number)
                .monospacedDigit()
                .foregroundStyle(.secondary)
                .accessibilityLabel(item.recipeCount == 1 ? "1 recipe" : "\(item.recipeCount) recipes")
        }
        .contentShape(.rect)
    }
}

/// The in-place text field a row turns into while it is being renamed, and the row the list grows at
/// the bottom while a new one is being added.
private struct ClassifierNameFieldView: View {
    /// What the button offered alongside a name collision does.
    enum ConflictAction {
        /// Renaming onto an existing name: fold this row into that one.
        case merge
        /// Creating a name that already exists: there is nothing to merge, so just go to it.
        case reveal
    }

    let prompt: String
    @Binding var name: String
    @FocusState.Binding var isFocused: Bool
    let conflict: LibraryClassifierEditor.NameConflict?
    let conflictAction: ConflictAction
    let classifier: LibraryClassifier
    let commit: () -> Void
    let endEditing: () -> Void
    let cancel: () -> Void
    let resolveConflict: () -> Void

    var body: some View {
        VStack(alignment: .leading) {
            TextField(prompt, text: $name)
                .focused($isFocused)
                .onSubmit(commit)
                .submitLabel(.done)
                // Category, course, and tag names are labels of the user's own choosing -- often
                // proper nouns iOS doesn't know ("Gochujang", "Bánh Mì"). Autocorrect rewrites those
                // on commit, and the row is saved before the substitution is noticed.
                .autocorrectionDisabled()
                #if os(macOS)
                .onExitCommand(perform: cancel)
                #endif

            if let conflict {
                HStack {
                    Text("“\(conflict.name)” already exists.")
                        .foregroundStyle(.secondary)
                    Button(conflictAction == .merge ? "Merge" : "Show", action: resolveConflict)
                        .buttonStyle(.borderless)
                }
                .font(.footnote)
                .accessibilityElement(children: .combine)
            }
        }
        // Focus is claimed here rather than by the list's editingID observer: the field of a row
        // that was just scrolled into view (creating in a long list) doesn't exist until this view
        // appears, and focus set on a view that doesn't exist yet is silently dropped.
        .onAppear {
            isFocused = true
        }
        .onChange(of: isFocused) { _, focused in
            guard !focused else { return }
            endEditing()
        }
        .accessibilityLabel("\(classifier.singularLabel) name")
    }
}

#Preview("Categories") {
    NavigationStack {
        LibraryClassifiersEditView(classifier: .category)
    }
}

#Preview("Tags") {
    NavigationStack {
        LibraryClassifiersEditView(classifier: .tag)
    }
}
