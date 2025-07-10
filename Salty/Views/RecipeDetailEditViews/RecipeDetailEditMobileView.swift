//
//  RecipeDetailView.swift
//  Salty
//
//  Created by Robert on 10/21/22.
//
//  This view is geared towards iOS; see RecipeDetailEditDesktopView for macOS-tailored view.
//

import SwiftUI

struct RecipeDetailEditMobileView: View {
    @Environment(\.dismiss) var dismiss
    @State private var viewModel: RecipeDetailEditViewModel
    
    init(recipe: Recipe) {
        self._viewModel = State(initialValue: RecipeDetailEditViewModel(recipe: recipe))
    }

    var body: some View {
        Form {
            Section(header: Text("Basic Information")) {
                TextField("Name:", text: $viewModel.recipe.name)
                TextField("Source:", text: $viewModel.recipe.source)
                TextField("Source Details:", text: $viewModel.recipe.sourceDetails)
                TextField("Yield:", text: $viewModel.recipe.yield)
                Toggle("Favorite:", isOn: $viewModel.recipe.isFavorite)
                Toggle("Want to make", isOn: $viewModel.recipe.wantToMake)
                LabeledContent("Rating:") {
                    RatingEditView(recipe: $viewModel.recipe)
                        .frame(maxWidth: 200)
                }
                LabeledContent("Difficulty:") {
                    DifficultyEditView(recipe: $viewModel.recipe)
                        .frame(maxWidth: 200)
                }
                LabeledContent("Categories:") {
                    Button("Select Categories") {
                        viewModel.showingEditCategoriesSheet.toggle()
                    }
                }
                LabeledContent {
                    RecipeImageEditView(recipe: $viewModel.recipe, imageFrameSize: 100)
                } label: {
                    VStack {
                        Text("Image:")
                    }
                }
                TextField("Introduction:", text: $viewModel.recipe.introduction, axis: .vertical)
                    .lineLimit(5...10)
            }
            Section(header: Text("Ingredients")) {
                VStack(alignment: .leading, spacing: 16) {
                    Button("Edit Ingredients") {
                        viewModel.showingEditIngredientsSheet.toggle()
                    }
                    .popover(isPresented: $viewModel.showingEditIngredientsSheet) {
                        IngredientsEditView(recipe: $viewModel.recipe)
                    }
                    if viewModel.recipe.ingredients.isEmpty {
                        Text("No ingredients added")
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(viewModel.recipe.ingredients) { ingredient in
                                if ingredient.isHeading {
                                    Text(ingredient.text)
                                        .font(.callout)
                                        .fontWeight(.semibold)
                                        //.padding(.top, 8)
                                } else {
                                    Text(ingredient.text)
                                        .font(.body)
                                }
                            }
                        }
                    }
                }
            }
            Section(header: Text("Directions")) {
                Button("Edit Directions") {
                    viewModel.showingEditDirectionsSheet.toggle()
                }
                .popover(isPresented: $viewModel.showingEditDirectionsSheet) {
                    DirectionsEditView(recipe: $viewModel.recipe)
                }
                if viewModel.recipe.directions.isEmpty {
                    Text("No directions added")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(viewModel.recipe.directions.enumerated()), id: \.element.id) { index, direction in
                            HStack(alignment: .top, spacing: 12) {
                                Text("\(index + 1).")
                                    .font(.body)
                                    .fontWeight(.medium)
                                    .foregroundColor(.secondary)
                                    .frame(width: 24, alignment: .leading)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    if let stepName = direction.stepName, !stepName.isEmpty {
                                        Text(stepName)
                                            .font(.callout)
                                            .fontWeight(.semibold)
                                    }
                                    Text(direction.text)
                                        .font(.body)
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
            
            Section(header: Text("Preparation Time")) {
                VStack(alignment: .leading, spacing: 16) {
                    Button("Edit Times") {
                        viewModel.showingEditPreparationTimes.toggle()
                    }
                    .popover(isPresented: $viewModel.showingEditPreparationTimes) {
                        PreparationTimesEditView(recipe: $viewModel.recipe)
                    }
                    
                    if viewModel.recipe.preparationTimes.isEmpty {
                        Text("No preparation times added")
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                    } else {
                        VStack(alignment: .leading, spacing: 8) {
                            ForEach(viewModel.recipe.preparationTimes) { preparationTime in
                                Label("\(preparationTime.type): \(preparationTime.timeString)", systemImage: "clock")
                            }
                        }
                    }
                }
            }
            
            Section(header: Text("Notes")) {
                Button("Edit Notes") {
                    viewModel.showingEditNotesSheet.toggle()
                }
                .popover(isPresented: $viewModel.showingEditNotesSheet) {
                    NotesEditView(recipe: $viewModel.recipe)
                }
                if viewModel.recipe.notes.isEmpty {
                    Text("No notes added")
                    .foregroundStyle(.secondary)
                    .padding(.vertical, 8)
                } else {
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(viewModel.recipe.notes) { note in
                            VStack(alignment: .leading, spacing: 4) {
                                if !note.title.isEmpty {
                                    Text(note.title)
                                        .fontWeight(.semibold)
                                }
                                Text(note.content)
                                    .font(.body)
                                    .lineLimit(6)
                            }
                            .padding(.vertical, 4)
                        }
                    }
                }
            }
        }
        .padding()
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
