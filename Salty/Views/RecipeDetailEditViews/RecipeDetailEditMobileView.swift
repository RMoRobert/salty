//
//  RecipeDetailView.swift
//  Salty
//
//  Created by Robert on 10/21/22, forked from combined view on 7/9/25
//
//  This view is geared towards iOS; see RecipeDetailEditDesktopView for macOS-tailored view.
//

import SwiftUI

struct RecipeDetailEditMobileView: View {
    @Environment(\.dismiss) var dismiss
    @State private var viewModel: RecipeDetailEditViewModel
    
    init(recipe: Recipe, isNewRecipe: Bool = false, onNewRecipeSaved: ((String) -> Void)? = nil) {
        self._viewModel = State(initialValue: RecipeDetailEditViewModel(recipe: recipe, isNewRecipe: isNewRecipe, onNewRecipeSaved: onNewRecipeSaved))
    }

    var body: some View {
        List {
            Section("Basic Information") {
                TextField("Name", text: $viewModel.recipe.name)
                TextField("Source", text: $viewModel.recipe.source)
                TextField("Source Details", text: $viewModel.recipe.sourceDetails)
                Stepper(viewModel.recipe.servings != nil ?
                        (viewModel.recipe.servings! > 1 ? "\(viewModel.recipe.servings!.description) servings"
                        : "\(viewModel.recipe.servings!.description) serving")
                        : "Servings",
                       value: Binding(
                           get: { viewModel.recipe.servings ?? 0 },
                           set: { viewModel.recipe.servings = $0 == 0 ? nil : $0 }
                       ),
                       in: 0...2000)
                    .foregroundColor(viewModel.recipe.servings != nil ? .primary : .secondary)
                TextField("Yield", text: $viewModel.recipe.yield)
                Toggle("Favorite", isOn: $viewModel.recipe.isFavorite)
                Toggle("Want to make", isOn: $viewModel.recipe.wantToMake)
                
                HStack {
                    Text("Rating")
                    Spacer()
                    RatingEditView(recipe: $viewModel.recipe)
                }
                
                HStack {
                    Text("Difficulty")
                    Spacer()
                    DifficultyEditView(recipe: $viewModel.recipe)
                }
                
                HStack {
                    Text("Categories")
                    Spacer()
                    Button("Select Categories") {
                        viewModel.showingEditCategoriesSheet.toggle()
                    }
                }
                .popover(isPresented: $viewModel.showingEditCategoriesSheet) {
                    CategoryEditView(recipe: $viewModel.recipe)
                }
                
                
                TextField("Introduction", text: $viewModel.recipe.introduction, axis: .vertical)
                    .lineLimit(5...10)
            }
            
            Section("Ingredients") {
                ForEach($viewModel.recipe.ingredients) { $ingredient in
                    TextField("Ingredient", text: $ingredient.text)
                        .font(ingredient.isHeading ? .headline : .body)
                        .fontWeight(ingredient.isHeading ? .semibold : .regular)
                }
                .onDelete { indexSet in
                    viewModel.recipe.ingredients.remove(atOffsets: indexSet)
                }
                .onMove { from, to in
                    viewModel.recipe.ingredients.move(fromOffsets: from, toOffset: to)
                }
                
                HStack {
                    Button(action: {
                        viewModel.recipe.ingredients.append(Ingredient(
                            id: UUID().uuidString,
                            isHeading: false,
                            isMain: false,
                            text: "New ingredient"
                        ))
                    }) {
                        Label("Add Ingredient", systemImage: "plus.circle.fill")
                    }
                    .labelStyle(.titleAndIcon)
                    //.buttonStyle(.bordered)
                    
                    Spacer()
                    Menu {
                        Button(action: {
                            viewModel.recipe.ingredients.append(Ingredient(
                                id: UUID().uuidString,
                                isHeading: true,
                                isMain: false,
                                text: "New Heading"
                            ))
                        }) {
                            Label("Add Heading", systemImage: "paragraphsign")
                        }
                        
                        Button(action: {
                            viewModel.showingBulkEditIngredientsSheet.toggle()
                        }) {
                            Label("Edit as Text (Bulk Edit)", systemImage: "text.alignleft")
                        }
                    } label: {
                        Label("More", systemImage: "ellipsis")
                            .padding([.top, .bottom], 5)
                    }
                    .labelStyle(.iconOnly)
                    .controlSize(.small)
                    .buttonStyle(.bordered)
                    .buttonBorderShape(.circle)
                    .padding(.trailing, -6)
                }
            }
            
            Section("Directions") {
                ForEach($viewModel.recipe.directions) { $direction in
                    TextField("Direction", text: $direction.text)
                        .font(direction.isHeading == true ? .headline : .body)
                        .fontWeight(direction.isHeading == true ? .semibold : .regular)
                }
                .onDelete { indexSet in
                    viewModel.recipe.directions.remove(atOffsets: indexSet)
                }
                .onMove { from, to in
                    viewModel.recipe.directions.move(fromOffsets: from, toOffset: to)
                }
                HStack {
                    Button(action: {
                        viewModel.recipe.directions.append(Direction(
                            id: UUID().uuidString,
                            isHeading: false,
                            text: "New step"
                        ))
                    }) {
                        Label("Add Step", systemImage: "plus.circle.fill")
                    }
                    .labelStyle(.titleAndIcon)
                    .buttonStyle(.bordered)
                    
                    Spacer()
                    
                    Menu {
                        Button(action: {
                            viewModel.recipe.directions.append(Direction(
                                id: UUID().uuidString,
                                isHeading: true,
                                text: "New Heading"
                            ))
                        }) {
                            Label("Add Heading", systemImage: "paragraphsign")
                        }
                        
                        Button(action: {
                            viewModel.showingBulkEditDirectionsSheet.toggle()
                        }) {
                            Label("Bulk Edit", systemImage: "text.alignleft")
                        }
                    } label: {
                        Label("More", systemImage: "ellipsis.circle")
                    }
                    .labelStyle(.iconOnly)
                    .foregroundColor(.accentColor)
                    .buttonStyle(.plain)
                }
            }
            
            Section("Preparation Time") {
                ForEach($viewModel.recipe.preparationTimes) { $preparationTime in
                    HStack {
                        TextField("Type", text: $preparationTime.type)
                            .font(.headline)
                            .fontWeight(.semibold)
                        TextField("Time", text: $preparationTime.timeString)
                            .font(.body)
                    }
                }
                .onDelete { indexSet in
                    viewModel.recipe.preparationTimes.remove(atOffsets: indexSet)
                }
                .onMove { from, to in
                    viewModel.recipe.preparationTimes.move(fromOffsets: from, toOffset: to)
                }
                
                HStack {
                    Button(action: {
                        viewModel.recipe.preparationTimes.append(PreparationTime(
                            id: UUID().uuidString,
                            type: "New Time",
                            timeString: "0 minutes"
                        ))
                    }) {
                        Label("Add Time", systemImage: "plus.circle.fill")
                    }
                    .labelStyle(.titleAndIcon)
                    .buttonStyle(.bordered)
                    
                    Spacer()
                    
                    Menu {
                        Button(action: {
                            // TODO: Implement bulk edit
                        }) {
                            Label("Bulk Edit", systemImage: "text.alignleft")
                        }
                        .disabled(true)
                    } label: {
                        Label("More", systemImage: "ellipsis.circle")
                    }
                    .labelStyle(.iconOnly)
                    .foregroundColor(.accentColor)
                    .buttonStyle(.plain)
                }
            }
            
            Section("Notes") {
                ForEach($viewModel.recipe.notes) { $note in
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Note title", text: $note.title)
                            .font(.headline)
                            .fontWeight(.semibold)
                        TextField("Note content", text: $note.content, axis: .vertical)
                            .font(.body)
                            .lineLimit(3...6)
                    }
                }
                .onDelete { indexSet in
                    viewModel.recipe.notes.remove(atOffsets: indexSet)
                }
                .onMove { from, to in
                    viewModel.recipe.notes.move(fromOffsets: from, toOffset: to)
                }
                
                HStack {
                    Button(action: {
                        viewModel.recipe.notes.append(Note(
                            id: UUID().uuidString,
                            title: "",
                            content: "New note content"
                        ))
                    }) {
                        Label("Add Note", systemImage: "plus.circle.fill")
                    }
                    .labelStyle(.titleAndIcon)
                    .buttonStyle(.bordered)
                    
                    Spacer()
                    
                    Menu {
                        Button(action: {
                            // TODO: Implement bulk edit
                        }) {
                            Label("Bulk Edit", systemImage: "text.alignleft")
                        }
                        .disabled(true)
                    } label: {
                        Label("More", systemImage: "ellipsis.circle")
                    }
                    .labelStyle(.iconOnly)
                    .foregroundColor(.accentColor)
                    .buttonStyle(.plain)
                }
            }
            
            Section("Photo") {
                RecipeImageEditView(recipe: $viewModel.recipe, imageFrameSize: 100)
            }
        }
        #if !os(macOS)
        .environment(\.editMode, .constant(.active))
        .navigationTitle("Edit Recipe")
        .navigationBarTitleDisplayMode(.inline)
        #endif
        .toolbar {
            ToolbarItemGroup {
                Button("Cancel") {
                    if viewModel.hasUnsavedChanges {
                        viewModel.showingCancelAlert = true
                    } else {
                        dismiss()
                    }
                }
                .buttonStyle(.bordered)
                .foregroundColor(.secondary)
                
                Button("Save") {
                    viewModel.saveRecipe()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(.accentColor)
            }
        }
        .alert("Discard Changes?", isPresented: $viewModel.showingCancelAlert) {
            Button("Cancel", role: .cancel) { }
            Button("Discard", role: .destructive) {
                viewModel.discardChanges()
                dismiss()
            }
        } message: {
            Text("You have unsaved changes. Are you sure you want to discard them?")
        }

        .sheet(isPresented: $viewModel.showingBulkEditIngredientsSheet) {
            RecipeIngredientsBulkEditView(recipe: $viewModel.recipe)
        }
        .sheet(isPresented: $viewModel.showingBulkEditDirectionsSheet) {
            RecipeDirectionsBulkEditView(recipe: $viewModel.recipe)
        }
        .interactiveDismissDisabled(viewModel.hasUnsavedChanges)
        .onKeyPress(.escape) {
            if viewModel.hasUnsavedChanges {
                viewModel.showingCancelAlert = true
                return .handled
            }
            return .ignored
        }
    }
}

#Preview {
    RecipeDetailEditMobileView(recipe: SampleData.sampleRecipes[0])
}
