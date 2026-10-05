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
    /// A row that was just added, for the list to scroll to and focus.
    @State private var newRowID: String?

    var showToolbar: Bool = true
    var showBottomButtons: Bool = false

    var body: some View {
        RecipeRowEditorShell(title: "Edit Ingredients", isStandalone: showToolbar, showsBottomButtons: showBottomButtons) {
            RecipeRowListEditor(
                items: $recipe.ingredients,
                newRowID: $newRowID,
                isStandalone: showToolbar,
                newRow: { .emptyRow() }
            ) { $ingredient, context in
                IngredientEditRowView(ingredient: $ingredient, context: context)
            }
        } actions: {
            // The split "New Ingredient" button, as it has always looked: click adds an ingredient,
            // the menu half holds the main-ingredient variant.
            ComboButtonRepresentable(
                title: "New Ingredient",
                image: NSImage(systemSymbolName: "plus.circle", accessibilityDescription: nil),
                menuItems: [
                    MenuItem(title: "Add New Main Ingredient", image: NSImage(named: "recipe-new-main-ingredient-image"), action: { add(.emptyRow(isHeading: false, isMain: true)) })
                ],
                onPrimaryAction: { add(.emptyRow()) }
            )
            .fixedSize()
            .keyboardShortcut("n", modifiers: [.command])

            Button("New Heading", systemImage: "folder.badge.plus") {
                add(.emptyRow(isHeading: true))
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
        }
    }

    private func add(_ ingredient: Ingredient) {
        withAnimation(.easeIn) {
            newRowID = RecipeItemListEditor.append(ingredient, to: &recipe.ingredients)
        }
    }
}

// MARK: - Ingredient Edit Row View

struct IngredientEditRowView: View {
    @Binding var ingredient: Ingredient
    let context: RecipeRowContext

    private var placeholder: String {
        ingredient.isHeadingRow ? "Heading Title" : "Ingredient"
    }

    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            // Text field column - flexible width
            TextField(placeholder, text: $ingredient.text, axis: .vertical)
                .font(ingredient.isHeadingRow ? .headline : .body)
                .fontWeight(ingredient.isHeadingRow ? .semibold : .regular)
                .lineLimit(1...3)
                .textFieldStyle(.plain)
                .focused(context.focus, equals: ingredient.id)
                .modifier(context.keyboardReordering)
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

                RecipeRowAddButton(context: context)
                    .frame(width: 24)

                RecipeRowDeleteButton(context: context)
                    .frame(width: 24)

                RecipeRowDragHandle(
                    context: context,
                    text: ingredient.text,
                    placeholder: placeholder,
                    isHeading: ingredient.isHeadingRow
                )
                .frame(width: 24)
            }
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 0)
        .background {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(context.isAlternateRow ? Color(nsColor: .tertiarySystemFill) : .clear)
        }
    }
}

struct MenuItem {
    let title: String
    let image: NSImage?
    let action: () -> Void
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
