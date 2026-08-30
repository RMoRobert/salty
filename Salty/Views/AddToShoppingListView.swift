//
//  AddToShoppingListView.swift
//  Salty
//
//  The sheet behind the ingredients box's "Add to List…" button: pick a destination, uncheck
//  anything you don't need, add. Anything the list already covers starts unchecked and says so.
//

import SwiftUI
import SaltyCore

struct AddToShoppingListView: View {
    @State private var viewModel: AddToShoppingListViewModel
    @Environment(\.dismiss) private var dismiss

    init(recipe: Recipe, scaleFactor: Double, scaleLabel: String? = nil) {
        _viewModel = State(wrappedValue: AddToShoppingListViewModel(
            recipe: recipe, scaleFactor: scaleFactor, scaleLabel: scaleLabel
        ))
    }

    var body: some View {
        NavigationStack {
            Form {
                DestinationSection(viewModel: viewModel)
                if !viewModel.candidates.isEmpty {
                    IngredientSelectionSection(viewModel: viewModel)
                }
            }
            #if os(macOS)
            .formStyle(.grouped)
            #endif
            .navigationTitle("Add to List")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel", role: .cancel) { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button(addButtonTitle) {
                        Task {
                            if await viewModel.save() { dismiss() }
                        }
                    }
                    .disabled(!viewModel.canSave)
                    .keyboardShortcut(.defaultAction)
                }
            }
            .errorAlert($viewModel.operationError)
        }
        .task {
            viewModel.prepareInitialSelection()
        }
        #if os(macOS)
        .frame(minWidth: 420, minHeight: 480)
        #endif
    }

    private var addButtonTitle: String {
        viewModel.selectedCount > 0 ? "Add \(viewModel.selectedCount) Item(s)" : "Add"
    }
}

/// Destination picker. A menu rather than a plain `Picker` so "New List" can sit above the lists as
/// an action: it closes the menu on use, which is what keeps a tap-happy moment from producing a
/// row of empty lists.
private struct DestinationSection: View {
    @Bindable var viewModel: AddToShoppingListViewModel
    @State private var isNamingNewList = false
    @State private var newListName = ""

    var body: some View {
        Section {
            #if os(macOS)
            // A macOS form label sits immediately left of the control it names and ends with a
            // colon (HIG). `LabeledContent` instead splits the row into two columns and left the
            // popup stranded mid-row, far from the words describing it.
            HStack {
                Text("Add To:")
                    // The words are the control's label, not a thing in their own right: hidden
                    // here and restated on the menu, so VoiceOver reads one "Add To, <list name>"
                    // element rather than a stray caption followed by an unlabelled pop-up.
                    .accessibilityHidden(true)
                ShoppingListMenuView(viewModel: viewModel, onCreateList: beginNamingNewList) {
                    Text(viewModel.selectedList?.name ?? "Choose a List")
                }
                // Natural width, bordered: a standard pull-down button rather than loose text with
                // a chevron floating after it.
                .menuStyle(.button)
                .fixedSize()
                .accessibilityLabel("Add To")
                Spacer()
            }
            #else
            // iOS keeps caption and value inside the menu's own label, so it already reads as a
            // single element -- nothing to reconnect.
            ShoppingListMenuView(viewModel: viewModel, onCreateList: beginNamingNewList) {
                DestinationMenuLabel(name: viewModel.selectedList?.name)
            }
            #endif
        } footer: {
            if let scaleLabel = viewModel.scaleLabel {
                Text("Amounts are scaled to \(scaleLabel)%.")
            }
        }
        .alert("New Shopping List", isPresented: $isNamingNewList) {
            TextField("List Name", text: $newListName)
            Button("Cancel", role: .cancel) { newListName = "" }
            Button("Create") {
                let name = newListName
                newListName = ""
                Task { await viewModel.createList(named: name) }
            }
        } message: {
            Text("The new list becomes this recipe's destination.")
        }
    }

    /// Opens the dialog on an empty field, so a name typed and then cancelled doesn't reappear the
    /// next time round.
    private func beginNamingNewList() {
        newListName = ""
        isNamingNewList = true
    }
}

/// The destination menu itself. Takes its label from the caller so each platform can present it the
/// way that platform labels controls, without a second copy of the menu contents.
private struct ShoppingListMenuView<Label: View>: View {
    @Bindable var viewModel: AddToShoppingListViewModel
    /// Raised rather than handled here: the naming dialog has to be presented by a view that
    /// outlives the menu, and menu content is gone the moment an item is chosen.
    let onCreateList: () -> Void
    @ViewBuilder var label: () -> Label

    var body: some View {
        Menu {
            // Trailing ellipsis: it opens a dialog now rather than creating on the spot.
            Button("Create New List…", systemImage: "plus", action: onCreateList)
            Divider()
            Picker("Add To", selection: $viewModel.selectedListId) {
                ForEach(viewModel.shoppingLists) { list in
                    Text("\(list.name) (\(viewModel.itemCount(of: list)))")
                        .tag(String?.some(list.id))
                }
            }
            .pickerStyle(.inline)
        } label: {
            label()
        }
        .onChange(of: viewModel.selectedListId) {
            viewModel.refreshDuplicates()
        }
    }
}

/// Built to read as an ordinary form picker row, since that's what it stands in for on iOS.
private struct DestinationMenuLabel: View {
    let name: String?

    var body: some View {
        HStack {
            Text("Add To")
                .foregroundStyle(.primary)
            Spacer()
            Text(name ?? "Choose a List")
                .foregroundStyle(.secondary)
                .lineLimit(1)
            Image(systemName: "chevron.up.chevron.down")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }
}

/// Every ingredient in one section, whether or not the recipe groups them. Group names appear as
/// disabled inline rows rather than section headers since headers split the list into pieces and
/// made "Select All"/"Deselect All" more difficult to use
private struct IngredientSelectionSection: View {
    @Bindable var viewModel: AddToShoppingListViewModel

    var body: some View {
        Section {
            ForEach(viewModel.groups) { group in
                if let heading = group.heading {
                    IngredientGroupHeadingRow(text: heading)
                }
                ForEach(group.items) { candidate in
                    IngredientSelectionRow(viewModel: viewModel, candidate: candidate)
                }
            }
        } header: {
            IngredientSectionHeader(viewModel: viewModel)
        } footer: {
            if let summary = viewModel.skippedSummary {
                Text(summary)
            }
        }
    }
}

/// Title plus the select-all action, in the section header rather than as a row: as a row it carried
/// its own checkmark and read as one more ingredient to tick.
///
/// Always the whole recipe -- ingredient groups don't get their own -- so there's one place to look
/// however the recipe is written. No font of its own: inheriting the header's keeps the action the
/// same size as the title beside it, whatever the platform makes that.
private struct IngredientSectionHeader: View {
    @Bindable var viewModel: AddToShoppingListViewModel

    var body: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Ingredients")
                #if os(iOS)
                .foregroundStyle(.secondary)
                #endif
            Spacer()
            Button(viewModel.isEverythingSelected ? "Deselect All" : "Select All") {
                viewModel.toggleSelectAll()
            }
            #if os(macOS)
            .buttonStyle(.link)
            #else
            .buttonStyle(.plain)
            .foregroundStyle(Color.accentColor)
            #endif
        }
        #if os(iOS)
        .font(.subheadline)
        #endif
    }
}

private struct IngredientGroupHeadingRow: View {
    let text: String

    var body: some View {
        Text(text)
            //.font(.caption)
            .foregroundStyle(.secondary)
            // Hugs the ingredients beneath it instead of reading as a row of its own.
            .listRowSeparator(.hidden, edges: .bottom)
    }
}

private struct IngredientSelectionRow: View {
    @Bindable var viewModel: AddToShoppingListViewModel
    let candidate: RecipeToShoppingList.CandidateItem

    var body: some View {
        Button {
            viewModel.toggle(candidate)
        } label: {
            HStack(alignment: .firstTextBaseline) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? Color.accentColor : .secondary)
                    .imageScale(.large)
                VStack(alignment: .leading) {
                    Text(candidate.text)
                        .foregroundStyle(.primary)
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                    if viewModel.isAlreadyOnList(candidate) {
                        Text("Found on this list")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer(minLength: 0)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private var isSelected: Bool { viewModel.isSelected(candidate) }
}

#Preview {
    AddToShoppingListView(recipe: SampleData.sampleRecipes[0], scaleFactor: 1.0)
}
