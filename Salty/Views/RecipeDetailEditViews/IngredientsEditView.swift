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
                ingredientsContent
                    .navigationTitle("Edit Ingredients")
                    .toolbar {
                        ToolbarItemGroup(placement: .automatic) {
                            Button {
                                addNewIngredient()
                            } label: {
                                Label("New Ingredient", systemImage: "plus.circle")
                            }
                            .keyboardShortcut("n", modifiers: [.command])
                            
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
                    #if os(macOS)
                    .presentationSizing(.fitted)
                    #endif
            } else {
                // Embedded view (no toolbar, no frame constraints)
                VStack(spacing: 0) {
                    ingredientsContent
                    if showBottomButtons {
                        bottomActionButtons
                            .padding(.top, 4)
                    }
                }
            }
        }
        .onAppear {
            editingIngredients = recipe.ingredients
        }
        .onDisappear {
            recipe.ingredients = editingIngredients
        }
    }
    
    private var ingredientsContent: some View {
        ScrollViewReader { proxy in
            Group {
                if showToolbar {
                    // Standalone view - add padding
                    ingredientsList
                        .padding(.horizontal)
                        .padding(.top)
                } else {
                    // Embedded view - no extra padding
                    ingredientsList
                }
            }
            .onChange(of: scrollToNewItem) { _, newID in
                if let newID = newID {
                    withAnimation {
                        proxy.scrollTo(newID, anchor: .center)
                    }
                    // Set focus after scrolling
                    DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                        focusedIngredientID = newID
                        scrollToNewItem = nil
                    }
                }
            }
        }
    }
    
    private var bottomActionButtons: some View {
        HStack {
            Button {
                addNewIngredient()
            } label: {
                Label("New Ingredient", systemImage: "plus.circle")
            }
            .keyboardShortcut("n", modifiers: [.command])
            
            Button {
                addNewHeading()
            } label: {
                Label("New Heading", systemImage: "folder.badge.plus")
            }
            .keyboardShortcut("n", modifiers: [.command, .shift])
            
            Spacer()
        }
        .padding(.top, 2)
    }
    
    private var ingredientsList: some View {
        VStack(spacing: 0) {
            ForEach(editingIngredients, id: \.id) { ingredient in
                if let index = editingIngredients.firstIndex(where: { $0.id == ingredient.id }),
                   index < editingIngredients.count {
                    dropIndicator(for: index)
                    ingredientRow(at: index)
                }
            }
            dropIndicatorAtEnd
        }
    }
    
    @ViewBuilder
    private func dropIndicator(for index: Int) -> some View {
        if let dropTarget = dropTargetIndex, dropTarget == index {
            Rectangle()
                .fill(Color.accentColor)
                .frame(height: 3)
                .padding(.horizontal, 20)
                .transition(.opacity.combined(with: .scale))
        }
    }
    
    @ViewBuilder
    private var dropIndicatorAtEnd: some View {
        let currentCount = editingIngredients.count
        if let dropTarget = dropTargetIndex, dropTarget == currentCount, currentCount >= 0 {
            Rectangle()
                .fill(Color.primary)
                .frame(height: 2)
                .padding(.horizontal, 20)
                .transition(.opacity.combined(with: .scale))
        }
    }
    
    @ViewBuilder
    private func ingredientRow(at index: Int) -> some View {
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
            IngredientEditRowView(
                ingredient: ingredientBinding,
                index: index,
                onAdd: { addIngredientAfter(index) },
                onDelete: { deleteIngredient(at: index) },
                onMove: { fromIndex, toIndex in
                    moveIngredient(from: fromIndex, to: toIndex)
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
            .focused($focusedIngredientID, equals: ingredient.id)
            .id(ingredient.id)
        }
    }
    
    private func addIngredientAfter(_ index: Int) {
        let newIngredient = Ingredient(
            id: UUID().uuidString,
            isHeading: false,
            isMain: false,
            text: "New ingredient"
        )
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            editingIngredients.insert(newIngredient, at: index + 1)
        }
        scrollToNewItem = newIngredient.id
        // Set focus after a brief delay to ensure the view is rendered
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
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
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            editingIngredients.remove(at: index)
        }
    }
    
    private func moveIngredient(from fromIndex: Int, to toIndex: Int) {
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            editingIngredients.move(fromOffsets: IndexSet(integer: fromIndex), toOffset: toIndex)
        }
    }
    
    private func addNewIngredient() {
        let newIngredient = Ingredient(
            id: UUID().uuidString,
            isHeading: false,
            isMain: false,
            text: "New ingredient"
        )
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            editingIngredients.append(newIngredient)
        }
        scrollToNewItem = newIngredient.id
        // Set focus after a brief delay to ensure the view is rendered
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            focusedIngredientID = newIngredient.id
        }
    }
    
    private func addNewHeading() {
        let newIngredient = Ingredient(
            id: UUID().uuidString,
            isHeading: true,
            isMain: false,
            text: "New heading"
        )
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            editingIngredients.append(newIngredient)
        }
        scrollToNewItem = newIngredient.id
        // Set focus after a brief delay to ensure the view is rendered
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.2) {
            focusedIngredientID = newIngredient.id
        }
    }
}

// MARK: - Ingredient Edit Row View

struct IngredientEditRowView: View {
    @Binding var ingredient: Ingredient
    let index: Int
    let onAdd: () -> Void
    let onDelete: () -> Void
    let onMove: (Int, Int) -> Void
    let onDragStart: () -> Void
    let onDragEnd: () -> Void
    let onDropTargetChanged: (Int?) -> Void
    
    @State private var isDragging = false
    @State private var isDropTarget = false
    
    var body: some View {
        HStack() {
            TextField("Ingredient", text: $ingredient.text, axis: .vertical)
                .font(ingredient.isHeading == true ? .headline : .body)
                .fontWeight(ingredient.isHeading == true ? .semibold : .regular)
                .lineLimit(1...3)
                .textFieldStyle(.squareBorder)
        
            
            Spacer()
                .frame(width: 2)
            
            // Action buttons - centered vertically
            VStack {
                HStack(spacing: 4) {
                    // Is Main/Star:
                    if ingredient.isHeading {
                        Spacer()
                            .frame(width: 4)
                    }
                    else {
                        Button {
                            ingredient.isMain.toggle()
                        } label: {
                            Label("Mark as main ingredient", systemImage: ingredient.isMain ? "star.fill" : "star")
                        }
                        .buttonStyle(.plain)
                        .labelStyle(.iconOnly)
                        .foregroundStyle(ingredient.isMain ? .yellow : .secondary)
                    }
                    // Add
                    Button {
                        onAdd()
                    } label: {
                        Label("Add", systemImage: "plus.circle.fill")
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .foregroundStyle(Color.accentColor)
                    // Delete:
                    Button {
                        onDelete()
                    } label: {
                        Label("Delete", systemImage: "minus.circle.fill")
                    }
                    .labelStyle(.iconOnly)
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)
                    
                    // Drag handle - only this can drag
                    Label("Drag to Move", systemImage: "line.3.horizontal")
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.tertiary)
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
            .frame(alignment: .center)
        }
        .padding(.vertical, 2)
        //.padding(.horizontal, 2)
        .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
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

#Preview {
    IngredientsEditView(recipe: .constant(SampleData.sampleRecipes[0]))
}

#endif
