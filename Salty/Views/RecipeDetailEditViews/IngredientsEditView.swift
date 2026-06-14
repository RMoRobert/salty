//
//  IngredientsEditView.swift
//  Salty
//
//  Created by Robert on 7/4/23.
//

#if os(macOS)

import SwiftUI

struct IngredientsEditView: View {
    @Binding var recipe: Recipe
    @State private var editingIngredients: [Ingredient] = []
    @State private var draggedItem: Ingredient?
    @State private var dropTargetIndex: Int?
    @State private var scrollToNewItem: String?
    @FocusState private var focusedIngredientID: String?
    @Environment(\.dismiss) private var dismiss
    
    var showToolbar: Bool = true
    var showBottomButtons: Bool = false
    
    var body: some View {
        Group {
            if showToolbar {
                // Standalone view with toolbar (for sheet presentation)
                IngredientsContentView(
                    editingIngredients: $editingIngredients,
                    showToolbar: showToolbar,
                    scrollToNewItem: $scrollToNewItem,
                    focusedIngredientID: $focusedIngredientID,
                    dropTargetIndex: $dropTargetIndex,
                    draggedItem: $draggedItem,
                    onAddIngredientAfter: { addIngredientAfter($0) },
                    onDeleteIngredient: { deleteIngredient(at: $0) },
                    onMoveIngredient: { moveIngredient(from: $0, to: $1) }
                )
                .navigationTitle("Edit Ingredients")
                .toolbar {
                    ToolbarItemGroup(placement: .automatic) {
                        Button {
                            addNewIngredient()
                        } label: {
                            Label("New Ingredient", systemImage: "plus.circle")
                        }
                        
                        Button {
                            addNewHeading()
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
                    IngredientsContentView(
                        editingIngredients: $editingIngredients,
                        showToolbar: showToolbar,
                        scrollToNewItem: $scrollToNewItem,
                        focusedIngredientID: $focusedIngredientID,
                        dropTargetIndex: $dropTargetIndex,
                        draggedItem: $draggedItem,
                        onAddIngredientAfter: { addIngredientAfter($0) },
                        onDeleteIngredient: { deleteIngredient(at: $0) },
                        onMoveIngredient: { moveIngredient(from: $0, to: $1) }
                    )
                    if showBottomButtons {
                        BottomActionButtonsView(
                            onAddNewIngredient: { addNewIngredient() },
                            onAddNewMainIngredient: { addNewMainIngredient() },
                            onAddNewHeading: { addNewHeading() }
                        )
                        .padding(.top, 4)
                    }
                }
            }
        }
        .onAppear {
            editingIngredients = recipe.ingredients
        }
        .onChange(of: recipe.ingredients) { _, newValue in
            // Update local state when recipe changes (e.g., from bulk edit)
            if editingIngredients != newValue {
                editingIngredients = newValue
            }
        }
        .onChange(of: editingIngredients) { _, newValue in
            recipe.ingredients = newValue
        }
        .onDisappear {
            recipe.ingredients = editingIngredients
        }
    }
    
    private func addIngredientAfter(_ index: Int) {
        let newIngredient = Ingredient(
            id: UUID().uuidString,
            isHeading: false,
            isMain: false,
            text: ""
        )
        withAnimation(.easeIn) {
            editingIngredients.insert(newIngredient, at: index + 1)
        }
        scrollToNewItem = newIngredient.id
        // Set focus after a brief delay to ensure the view is rendered
        Task {
            try? await Task.sleep(for: .seconds(0.2))
            focusedIngredientID = newIngredient.id
        }
    }
    
    private func deleteIngredient(at index: Int) {
        guard index >= 0 && index < editingIngredients.count else { return }
        // Clear or adjust drop target if needed
        if let dropTarget = dropTargetIndex {
            if dropTarget == index {
                // Clear if deleting the drop target itself
                dropTargetIndex = nil
            } else if dropTarget > index {
                // Adjust drop target index if item before it is deleted
                dropTargetIndex = dropTarget - 1
            }
            // If dropTarget < index, no adjustment needed
        }
        withAnimation(.easeIn)  {
            _ = editingIngredients.remove(at: index)
        }
    }
    
    private func moveIngredient(from fromIndex: Int, to toIndex: Int) {
        withAnimation(.snappy)  {
            editingIngredients.move(fromOffsets: IndexSet(integer: fromIndex), toOffset: toIndex)
        }
    }
    
    private func addNewIngredient(isMain: Bool, isHeading: Bool) {
        let newIngredient = Ingredient(
            id: UUID().uuidString,
            isHeading: isMain ? false : isHeading,
            isMain: isMain,
            text: ""
        )
        withAnimation(.easeIn)  {
            editingIngredients.append(newIngredient)
        }
        scrollToNewItem = newIngredient.id
        // Set focus after a brief delay to ensure the view is rendered
        Task {
            try? await Task.sleep(for: .seconds(0.2))
            focusedIngredientID = newIngredient.id
        }
    }
    
    private func addNewIngredient() {
        addNewIngredient(isMain: false, isHeading: false)
    }
    
    private func addNewMainIngredient() {
        addNewIngredient(isMain: true, isHeading: false)
    }
    
    private func addNewHeading() {
        addNewIngredient(isMain: false, isHeading: true)
    }
}

// MARK: - Supporting Views

struct IngredientsContentView: View {
    @Binding var editingIngredients: [Ingredient]
    let showToolbar: Bool
    @Binding var scrollToNewItem: String?
    var focusedIngredientID: FocusState<String?>.Binding
    @Binding var dropTargetIndex: Int?
    @Binding var draggedItem: Ingredient?
    let onAddIngredientAfter: (Int) -> Void
    let onDeleteIngredient: (Int) -> Void
    let onMoveIngredient: (Int, Int) -> Void
    
    var body: some View {
        ScrollViewReader { proxy in
            Group {
                if showToolbar {
                    // Standalone view - add padding
                    IngredientsListView(
                        editingIngredients: $editingIngredients,
                        dropTargetIndex: $dropTargetIndex,
                        focusedIngredientID: focusedIngredientID,
                        onAddIngredientAfter: onAddIngredientAfter,
                        onDeleteIngredient: onDeleteIngredient,
                        onMoveIngredient: onMoveIngredient,
                        draggedItem: $draggedItem
                    )
                    .padding(.horizontal)
                    .padding(.top)
                } else {
                    // Embedded view - no extra padding
                    IngredientsListView(
                        editingIngredients: $editingIngredients,
                        dropTargetIndex: $dropTargetIndex,
                        focusedIngredientID: focusedIngredientID,
                        onAddIngredientAfter: onAddIngredientAfter,
                        onDeleteIngredient: onDeleteIngredient,
                        onMoveIngredient: onMoveIngredient,
                        draggedItem: $draggedItem
                    )
                }
            }
            .onChange(of: scrollToNewItem) { _, newID in
                if let newID = newID {
                    withAnimation(.easeOut) {
                        proxy.scrollTo(newID, anchor: .center)
                    }
                    // Set focus after scrolling
                    Task {
                        try? await Task.sleep(for: .seconds(0.2))
                        focusedIngredientID.wrappedValue = newID
                        scrollToNewItem = nil
                    }
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
    @Binding var editingIngredients: [Ingredient]
    @Binding var dropTargetIndex: Int?
    var focusedIngredientID: FocusState<String?>.Binding
    let onAddIngredientAfter: (Int) -> Void
    let onDeleteIngredient: (Int) -> Void
    let onMoveIngredient: (Int, Int) -> Void
    @Binding var draggedItem: Ingredient?
    
    var body: some View {
        VStack(spacing: 0) {
            ForEach(editingIngredients, id: \.id) { ingredient in
                if let index = editingIngredients.firstIndex(where: { $0.id == ingredient.id }),
                   index < editingIngredients.count {
                    DropIndicatorView(dropTargetIndex: $dropTargetIndex, index: index)
                    IngredientRowView(
                        editingIngredients: $editingIngredients,
                        index: index,
                        focusedIngredientID: focusedIngredientID,
                        dropTargetIndex: $dropTargetIndex,
                        draggedItem: $draggedItem,
                        onAddIngredientAfter: onAddIngredientAfter,
                        onDeleteIngredient: onDeleteIngredient,
                        onMoveIngredient: onMoveIngredient
                    )
                }
            }
            DropIndicatorAtEndView(
                editingIngredients: $editingIngredients,
                dropTargetIndex: $dropTargetIndex
            )
        }
    }
}

struct DropIndicatorView: View {
    @Binding var dropTargetIndex: Int?
    let index: Int
    
    var body: some View {
        if let dropTarget = dropTargetIndex, dropTarget == index {
            Rectangle()
                .fill(Color.accentColor)
                .frame(height: 3)
                .padding(.horizontal, 20)
                .transition(.opacity.combined(with: .scale))
        }
    }
}

struct DropIndicatorAtEndView: View {
    @Binding var editingIngredients: [Ingredient]
    @Binding var dropTargetIndex: Int?
    
    var body: some View {
        let currentCount = editingIngredients.count
        if let dropTarget = dropTargetIndex, dropTarget == currentCount, currentCount >= 0 {
            Rectangle()
                .fill(Color.primary)
                .frame(height: 2)
                .padding(.horizontal, 20)
                .transition(.opacity.combined(with: .scale))
        }
    }
}

struct IngredientRowView: View {
    @Binding var editingIngredients: [Ingredient]
    let index: Int
    var focusedIngredientID: FocusState<String?>.Binding
    @Binding var dropTargetIndex: Int?
    @Binding var draggedItem: Ingredient?
    let onAddIngredientAfter: (Int) -> Void
    let onDeleteIngredient: (Int) -> Void
    let onMoveIngredient: (Int, Int) -> Void
    
    var body: some View {
        // Ensure index is valid before accessing - double check to prevent race conditions
        if index >= 0 && index < editingIngredients.count {
            let ingredient = editingIngredients[index]
            // Create a safe binding that checks bounds
            let ingredientBinding = Binding<Ingredient>(
                get: {
                    guard index >= 0 && index < editingIngredients.count else {
                        return ingredient
                    }
                    return editingIngredients[index]
                },
                set: { newValue in
                    guard index >= 0 && index < editingIngredients.count else { return }
                    editingIngredients[index] = newValue
                }
            )
            // Alternating background colors for list effect
            let backgroundColor = (index % 2 == 0 || editingIngredients.count < 3)
                ? Color.clear
                : Color(nsColor: .tertiarySystemFill)
            IngredientEditRowView(
                ingredient: ingredientBinding,
                index: index,
                backgroundColor: backgroundColor,
                focusedIngredientID: focusedIngredientID,
                ingredientID: ingredient.id,
                onAdd: { onAddIngredientAfter(index) },
                onDelete: { onDeleteIngredient(index) },
                onMove: { fromIndex, toIndex in
                    onMoveIngredient(fromIndex, toIndex)
                },
                onDragStart: {
                    draggedItem = ingredient
                },
                onDragEnd: {
                    draggedItem = nil
                    dropTargetIndex = nil
                },
                onDropTargetChanged: { targetIndex in
                    dropTargetIndex = targetIndex
                }
            )
            .id(ingredient.id)
        }
    }
}

// MARK: - Ingredient Edit Row View

struct IngredientEditRowView: View {
    @Binding var ingredient: Ingredient
    let index: Int
    let backgroundColor: Color
    var focusedIngredientID: FocusState<String?>.Binding
    let ingredientID: String
    let onAdd: () -> Void
    let onDelete: () -> Void
    let onMove: (Int, Int) -> Void
    let onDragStart: () -> Void
    let onDragEnd: () -> Void
    let onDropTargetChanged: (Int?) -> Void
    
    @State private var isDragging = false
    @State private var isDropTarget = false
    
    var body: some View {
        HStack(alignment: .center, spacing: 3) {
            // Text field column - flexible width
            TextField(ingredient.isHeading ? "Heading Title" : "Ingredient", text: $ingredient.text, axis: .vertical)
                .font(ingredient.isHeading == true ? .headline : .body)
                .fontWeight(ingredient.isHeading == true ? .semibold : .regular)
                .lineLimit(1...3)
                .textFieldStyle(.plain)
                .focused(focusedIngredientID, equals: ingredientID)
                .padding([.top, .bottom], 2)
                .frame(maxWidth: .infinity, alignment: .leading)
            
            // Icon columns
            HStack(alignment: .center, spacing: 0) {
                // "Is main?" column
                Group {
                    if !ingredient.isHeading {
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
                
                // Drag handle column - fixed width
                Label("Drag to Move", systemImage: "line.3.horizontal")
                    .labelStyle(.iconOnly)
                    .foregroundStyle(.tertiary)
                    .frame(width: 24)
                    .draggable(String(index)) {
                        Label("Drag to Move", systemImage: "line.3.horizontal")
                            .labelStyle(.iconOnly)
                            .foregroundStyle(.tertiary)
                    }
                    .onDrag {
                        isDragging = true
                        onDragStart()
                        return NSItemProvider(object: String(index) as NSString)
                    }
            }
        }
        .padding(.vertical, 2)
        .padding(.horizontal, 0)
        .background {
            RoundedRectangle(cornerRadius: 6, style: .continuous)
                .fill(backgroundColor)
        }
        .opacity(isDragging ? 0.4 : 1.0)
        .scaleEffect(isDragging ? 0.95 : 1.0)
        .animation(.spring, value: isDragging)
        .dropDestination(for: String.self) { draggedIndices, location in
            guard let draggedIndexString = draggedIndices.first,
                  let draggedIndex = Int(draggedIndexString),
                  draggedIndex != index else {
                isDragging = false
                onDragEnd()
                return false
            }
            onMove(draggedIndex, draggedIndex < index ? index + 1 : index)
            isDragging = false
            onDragEnd()
            return true
        } isTargeted: { isTargeted in
            isDropTarget = isTargeted
            onDropTargetChanged(isTargeted ? index : nil)
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

