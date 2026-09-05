//
//  IngredientsEditView.swift
//  Salty
//
//  Created by Robert on 7/4/23.
//

import SaltyCore
#if os(macOS)

import SwiftUI

struct IngredientsEditView: View {
    @Binding var recipe: Recipe
    /// Where a dragged row would land, or nil when nothing is being dragged over the list.
    @State private var dropTarget: RecipeItemListEditor.DropTarget?
    /// A row that was just added: scrolled to and focused, then cleared.
    @State private var scrollToNewItem: String?
    @FocusState private var focusedIngredientID: String?
    @Environment(\.dismiss) private var dismiss

    var showToolbar: Bool = true
    var showBottomButtons: Bool = false

    var body: some View {
        Group {
            if showToolbar {
                // Standalone view with toolbar (for sheet presentation)
                content
                    .navigationTitle("Edit Ingredients")
                    .toolbar {
                        ToolbarItemGroup(placement: .automatic) {
                            Button {
                                addIngredient()
                            } label: {
                                Label("New Ingredient", systemImage: "plus.circle")
                            }

                            Button {
                                addHeading()
                            } label: {
                                Label("New Heading", systemImage: "folder.badge.plus")
                            }
                            .keyboardShortcut("n", modifiers: [.command, .shift])
                        }

                        ToolbarItem(placement: .confirmationAction) {
                            Button("Done") {
                                dismiss()
                            }
                            .keyboardShortcut(.return, modifiers: [.command])
                        }
                    }
                    .frame(minWidth: 600, idealWidth: 700, maxWidth: 800,
                           minHeight: 500, idealHeight: 600, maxHeight: 800)
                    .presentationSizing(.fitted)
            } else {
                // Embedded view (no toolbar, no frame constraints)
                VStack(spacing: 0) {
                    content
                    if showBottomButtons {
                        BottomActionButtonsView(
                            onAddNewIngredient: { addIngredient() },
                            onAddNewMainIngredient: { addMainIngredient() },
                            onAddNewHeading: { addHeading() }
                        )
                        .padding(.top, 4)
                    }
                }
            }
        }
    }

    private var content: some View {
        IngredientsContentView(
            ingredients: $recipe.ingredients,
            dropTarget: $dropTarget,
            scrollToNewItem: $scrollToNewItem,
            focusedIngredientID: $focusedIngredientID,
            showToolbar: showToolbar
        )
    }

    // MARK: - Adding

    private func addIngredient() {
        append(.emptyRow(isHeading: false))
    }

    private func addMainIngredient() {
        append(.emptyRow(isHeading: false, isMain: true))
    }

    private func addHeading() {
        append(.emptyRow(isHeading: true))
    }

    private func append(_ ingredient: Ingredient) {
        withAnimation(.easeIn) {
            scrollToNewItem = RecipeItemListEditor.append(ingredient, to: &recipe.ingredients)
        }
    }
}

// MARK: - Supporting Views

struct IngredientsContentView: View {
    @Binding var ingredients: [Ingredient]
    @Binding var dropTarget: RecipeItemListEditor.DropTarget?
    @Binding var scrollToNewItem: String?
    var focusedIngredientID: FocusState<String?>.Binding
    let showToolbar: Bool

    var body: some View {
        ScrollViewReader { proxy in
            IngredientsListView(
                ingredients: $ingredients,
                dropTarget: $dropTarget,
                scrollToNewItem: $scrollToNewItem,
                focusedIngredientID: focusedIngredientID
            )
            // Standalone gets its own padding; embedded takes the host's.
            .padding(.horizontal, showToolbar ? nil : 0)
            .padding(.top, showToolbar ? nil : 0)
            .onChange(of: scrollToNewItem) { _, newID in
                guard let newID else { return }
                withAnimation(.easeOut) {
                    proxy.scrollTo(newID, anchor: .center)
                }
                // Focus once the row has been laid out.
                Task {
                    try? await Task.sleep(for: .seconds(0.2))
                    focusedIngredientID.wrappedValue = newID
                    scrollToNewItem = nil
                }
            }
        }
    }
}

struct BottomActionButtonsView: View {
    let onAddNewIngredient: () -> Void
    let onAddNewMainIngredient: () -> Void
    let onAddNewHeading: () -> Void

    var body: some View {
        HStack {
            ComboButtonRepresentable(
                title: "New Ingredient",
                image: NSImage(systemSymbolName: "plus.circle", accessibilityDescription: nil),
                menuItems: [
                    MenuItem(title: "Add New Main Ingredient", image: NSImage(named: "recipe-new-main-ingredient-image"), action: onAddNewMainIngredient)
                ],
                onPrimaryAction: onAddNewIngredient
            )
            .fixedSize()
            .keyboardShortcut("n", modifiers: [.command])

            Button {
                onAddNewHeading()
            } label: {
                Label("New Heading", systemImage: "folder.badge.plus")
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])

            Spacer()
        }
        .padding(.top, 2)
    }
}

struct MenuItem {
    let title: String
    let image: NSImage?
    let action: () -> Void
}

struct IngredientsListView: View {
    @Binding var ingredients: [Ingredient]
    @Binding var dropTarget: RecipeItemListEditor.DropTarget?
    @Binding var scrollToNewItem: String?
    var focusedIngredientID: FocusState<String?>.Binding

    var body: some View {
        VStack(spacing: 0) {
            ForEach(ingredients) { ingredient in
                let id = ingredient.id
                RecipeListDropIndicator(isActive: dropTarget == .above(id))
                IngredientEditRowView(
                    ingredient: RecipeItemListEditor.binding(for: id, in: $ingredients, fallback: ingredient),
                    isAlternateRow: RecipeItemListEditor.isAlternateRow(id: id, in: ingredients),
                    focusedIngredientID: focusedIngredientID,
                    onAdd: { addIngredient(below: id) },
                    onDelete: { delete(id: id) },
                    onDrop: { droppedID in move(droppedID, to: .above(id)) },
                    onDropTargetChanged: { isTargeted in setDropTarget(.above(id), isTargeted: isTargeted) },
                    onMoveUp: { moveUp(id: id) },
                    onMoveDown: { moveDown(id: id) }
                )
                .id(id)
            }
            RecipeListEndDropZone(
                isActive: dropTarget == .end,
                onDrop: { droppedID in move(droppedID, to: .end) },
                onDropTargetChanged: { isTargeted in setDropTarget(.end, isTargeted: isTargeted) }
            )
        }
    }

    // MARK: - Editing

    private func addIngredient(below id: String) {
        withAnimation(.easeIn) {
            scrollToNewItem = RecipeItemListEditor.insert(
                .emptyRow(isHeading: false),
                below: id,
                in: &ingredients
            )
        }
    }

    private func delete(id: String) {
        withAnimation(.easeIn) {
            RecipeItemListEditor.delete(id: id, from: &ingredients)
        }
    }

    private func move(_ id: String, to target: RecipeItemListEditor.DropTarget) -> Bool {
        var moved = false
        withAnimation(.snappy) {
            moved = RecipeItemListEditor.move(id: id, to: target, in: &ingredients)
            dropTarget = nil
        }
        return moved
    }

    private func moveUp(id: String) -> Bool {
        withAnimation(.snappy) {
            RecipeItemListEditor.moveUp(id: id, in: &ingredients)
        }
    }

    private func moveDown(id: String) -> Bool {
        withAnimation(.snappy) {
            RecipeItemListEditor.moveDown(id: id, in: &ingredients)
        }
    }

    /// Only the row currently being hovered clears the indicator: dragging from one row to the next
    /// reports the new row as targeted before the old one reports that it isn't.
    private func setDropTarget(_ target: RecipeItemListEditor.DropTarget, isTargeted: Bool) {
        if isTargeted {
            dropTarget = target
        } else if dropTarget == target {
            dropTarget = nil
        }
    }
}

// MARK: - Ingredient Edit Row View

struct IngredientEditRowView: View {
    @Binding var ingredient: Ingredient
    let isAlternateRow: Bool
    var focusedIngredientID: FocusState<String?>.Binding
    let onAdd: () -> Void
    let onDelete: () -> Void
    /// Returns whether the drop was accepted.
    let onDrop: (String) -> Bool
    let onDropTargetChanged: (Bool) -> Void
    /// Each returns whether the row actually moved.
    let onMoveUp: () -> Bool
    let onMoveDown: () -> Bool

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            // Text field column - flexible width
            TextField(ingredient.isHeadingRow ? "Heading Title" : "Ingredient", text: $ingredient.text, axis: .vertical)
                .font(ingredient.isHeadingRow ? .headline : .body)
                .fontWeight(ingredient.isHeadingRow ? .semibold : .regular)
                .lineLimit(1...3)
                .textFieldStyle(.plain)
                .focused(focusedIngredientID, equals: ingredient.id)
                .modifier(RecipeRowKeyboardReordering(onMoveUp: onMoveUp, onMoveDown: onMoveDown))
                .padding([.top, .bottom], 2)
                .frame(maxWidth: .infinity, alignment: .leading)

            // Icon columns
            HStack(alignment: .center, spacing: 0) {
                // "Is main?" column
                Group {
                    if !ingredient.isHeadingRow {
                        Toggle(isOn: $ingredient.isMain) {
                            Label("Is main ingredient?", systemImage: ingredient.isMain ? "medal.fill" : "medal")
                        }
                        .help("Is main ingredient?")
                        .toggleStyle(.button)
                        .buttonStyle(.plain)
                        .labelStyle(.iconOnly)
                        .foregroundStyle(ingredient.isMain ? Color.blue : .secondary)
                        .opacity(ingredient.isMain ? 1 : 0.7)
                    }
                    else {
                        Spacer()
                            .frame(width: 4, height: 4)
                    }
                }
                .frame(width: 30)

                // Add button column
                Button {
                    onAdd()
                } label: {
                    Label("Add", systemImage: "plus.circle.fill")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(Color.green)
                .frame(width: 24)

                // Delete button column
                Button {
                    onDelete()
                } label: {
                    Label("Delete", systemImage: "minus.circle.fill")
                }
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .foregroundStyle(.red)
                .frame(width: 24)

                // Drag handle column - fixed width. The payload is the row's id, so a drop can tell a
                // real row from a stray text drag and never acts on a stale index.
                Label("Drag to Move", systemImage: "line.3.horizontal")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.tertiary)
                    .frame(width: 24)
                    .draggable(ingredient.id) {
                        Label("Drag to Move", systemImage: "line.3.horizontal")
                            .labelStyle(.iconOnly)
                            .foregroundStyle(.tertiary)
                    }
            }
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 0)
        .background {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(isAlternateRow ? Color(nsColor: .tertiarySystemFill) : .clear)
        }
        .dropDestination(for: String.self) { droppedIDs, _ in
            guard let droppedID = droppedIDs.first else { return false }
            return onDrop(droppedID)
        } isTargeted: { isTargeted in
            onDropTargetChanged(isTargeted)
        }
    }
}


struct ComboButtonRepresentable: NSViewRepresentable {
    var title: String
    var image: NSImage?
    var style: NSComboButton.Style = .split // or .unified
    var menuItems: [MenuItem]
    var onPrimaryAction: () -> Void

    // Helper to create an image with leading padding -- matches SwiftUI button labels with images better:
    private func paddedImage(from image: NSImage?, leadingPadding: CGFloat = 6) -> NSImage? {
        guard let originalImage = image else { return image }

        let padding: CGFloat = leadingPadding
        let newSize = NSSize(width: originalImage.size.width + padding, height: originalImage.size.height)
        let paddedImage = NSImage(size: newSize)

        paddedImage.lockFocus()
        originalImage.draw(
            at: NSPoint(x: padding, y: 0),
            from: NSRect(origin: .zero, size: originalImage.size),
            operation: .sourceOver,
            fraction: 1.0
        )
        paddedImage.unlockFocus()

        return paddedImage
    }

    func makeNSView(context: Context) -> NSComboButton {
        let menu = NSMenu()
        for (index, menuItem) in menuItems.enumerated() {
            let nsMenuItem = NSMenuItem(title: menuItem.title, action: #selector(Coordinator.menuItemAction(_:)), keyEquivalent: "")
            nsMenuItem.target = context.coordinator
            nsMenuItem.tag = index
            nsMenuItem.image = menuItem.image
            menu.addItem(nsMenuItem)
        }
        context.coordinator.menuActions = menuItems.map { $0.action }

        let comboButton = NSComboButton(title: title, menu: menu, target: context.coordinator, action: #selector(Coordinator.primaryAction))
        comboButton.style = style
        if let image = image {
            comboButton.image = paddedImage(from: image)
        }
        return comboButton
    }

    func updateNSView(_ nsView: NSComboButton, context: Context) {
        nsView.title = title
        nsView.image = paddedImage(from: image)
        nsView.style = style

        // Update menu
        let menu = NSMenu()
        for (index, menuItem) in menuItems.enumerated() {
            let nsMenuItem = NSMenuItem(title: menuItem.title, action: #selector(Coordinator.menuItemAction(_:)), keyEquivalent: "")
            nsMenuItem.target = context.coordinator
            nsMenuItem.tag = index
            nsMenuItem.image = menuItem.image
            menu.addItem(nsMenuItem)
        }
        nsView.menu = menu
        context.coordinator.menuActions = menuItems.map { $0.action }
        context.coordinator.onPrimaryAction = onPrimaryAction
    }

    func makeCoordinator() -> Coordinator {
        Coordinator(onPrimaryAction: onPrimaryAction, menuActions: menuItems.map { $0.action })
    }

    class Coordinator: NSObject {
        var onPrimaryAction: () -> Void
        var menuActions: [() -> Void] = []

        init(onPrimaryAction: @escaping () -> Void, menuActions: [() -> Void] = []) {
            self.onPrimaryAction = onPrimaryAction
            self.menuActions = menuActions
        }

        @objc func primaryAction() {
            onPrimaryAction()
        }

        @objc func menuItemAction(_ sender: NSMenuItem) {
            let index = sender.tag
            if index >= 0 && index < menuActions.count {
                menuActions[index]()
            }
        }
    }
}

#Preview {
    IngredientsEditView(recipe: .constant(SampleData.sampleRecipes[0]), showToolbar: false, showBottomButtons: true)
}

#endif
