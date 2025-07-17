//
//  RecipeDetailView.swift
//  Salty
//
//  Created by Robert on 10/21/22, forked from combined view on 7/9/25
//
//  This view is geared towards iOS; see RecipeDetailEditDesktopView for macOS-tailored view.
//

import SwiftUI
import Flow

struct RecipeDetailEditMobileView: View {
    @Environment(\.dismiss) var dismiss
    @State private var viewModel: RecipeDetailEditViewModel
    
    @State private var showingAddTagAlert = false
    @State private var newTagName = ""
    
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
                    Text("Course")
                    Spacer()
                    Button("Select Course") {
                        viewModel.showingEditCourseSheet.toggle()
                    }
                }
                
                HStack {
                    Text("Categories")
                    Spacer()
                    Button("Select Categories") {
                        viewModel.showingEditCategoriesSheet.toggle()
                    }
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
                            .modifier(EllipsisLabelPadding())
                    }
                    .modifier(EllipsisButtonModifier())
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
                        Label("More", systemImage: "ellipsis")
                            .modifier(EllipsisLabelPadding())
                    }
                    .modifier(EllipsisButtonModifier())
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
                    
                    Spacer()
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
                    
                    Spacer()
                }
            }
            
            
            // Tags
            Section("Tags") {
                HFlow(itemSpacing: 8, rowSpacing: 4) {
                    ForEach(viewModel.recipe.tags, id: \.self) { tag in
                        Button(action: {
                            viewModel.removeTag(tag)
                        }) {
                            Label(tag, systemImage: "minus.circle")
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.quaternary, in: Capsule())
                                .foregroundColor(.primary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Remove tag \(tag)")
                    }
                    
                }                
                Button(action: {
                    newTagName = ""
                    showingAddTagAlert = true
                }) {
                    Label("Add Tag", systemImage: "plus.circle.fill")
                }
                .labelStyle(.titleAndIcon)
        }
            
            Section("Nutrition Information:") {
                
                if let nutrition = viewModel.recipe.nutrition {
                    let parts = [
                        nutrition.servingSize.map { "Serving Size: \($0)" },
                        nutrition.calories.map { "Calories: \($0.formatted())" },
                        nutrition.fat.map { "Total fat: \($0.formatted())g" },
                        nutrition.saturatedFat.map { "Saturated Fat: \($0.formatted())g" },
                        nutrition.transFat.map { "Trans Fat: \($0.formatted())g" },
                        nutrition.cholesterol.map { "Cholesterol: \($0.formatted())mg" },
                        nutrition.sodium.map { "Sodium: \($0.formatted())mg" },
                        nutrition.carbohydrates.map { "Total Carbs: \($0.formatted())g" },
                        nutrition.fiber.map { "Fiber: \($0.formatted())g" },
                        nutrition.sugar.map { "Sugars: \($0.formatted())g" },
                        nutrition.protein.map { "Protein: \($0.formatted())g" }
                    ].compactMap { $0 }
                    
                    if parts.isEmpty {
                        Button("Add Nutrition Info", systemImage: "plus.circle.fill") {
                            viewModel.showingNutritionEditSheet.toggle()
                        }
                    }
                    else {
                        Text(parts.joined(separator: ", "))
                            .padding(.vertical, 8)
                            .font(.caption)
                        Button("Edit Nutrition Info", systemImage: "pencil") {
                            viewModel.showingNutritionEditSheet.toggle()
                        }
                    }
                }
                else {
                    Button("Add Nutrition Info", systemImage: "plus.circle.fill") {
                        viewModel.showingNutritionEditSheet.toggle()
                    }
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
                Button("Cancel", role: .cancel) {
                    if viewModel.hasUnsavedChanges {
                        viewModel.showingCancelAlert = true
                    } else {
                        dismiss()
                    }
                }
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
        .alert("Add Tag", isPresented: $showingAddTagAlert) {
            TextField("Tag name", text: $newTagName)
            Button("Cancel", role: .cancel) {
                newTagName = ""
            }
            Button("Add") {
                if !newTagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    viewModel.addTag(newTagName.trimmingCharacters(in: .whitespacesAndNewlines))
                    newTagName = ""
                }
            }
        } message: {
            Text("Enter a name for the new tag")
        }

        .sheet(isPresented: $viewModel.showingBulkEditIngredientsSheet) {
            RecipeIngredientsBulkEditView(recipe: $viewModel.recipe)
        }
        .sheet(isPresented: $viewModel.showingBulkEditDirectionsSheet) {
            RecipeDirectionsBulkEditView(recipe: $viewModel.recipe)
        }
        .sheet(isPresented: $viewModel.showingEditCategoriesSheet) {
            NavigationStack {
                CategoryEditView(recipe: $viewModel.recipe)
                    .navigationTitle("Select Categories")
#if !os(macOS)
                    .navigationBarTitleDisplayMode(.inline)
#endif
            }
        }
        .sheet(isPresented: $viewModel.showingEditCourseSheet) {
            NavigationStack {
                CourseEditView(recipe: $viewModel.recipe)
                    .navigationTitle("Select Course")
#if !os(macOS)
                    .navigationBarTitleDisplayMode(.inline)
#endif
            }
        }
        .sheet(isPresented: $viewModel.showingNutritionEditSheet) {
            NutritionEditView(recipe: $viewModel.recipe)
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


struct EllipsisButtonModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .labelStyle(.iconOnly)
            .controlSize(.small)
            .buttonStyle(.bordered)
            .buttonBorderShape(.circle)
            .padding(.trailing, -6)
    }
}

struct EllipsisLabelPadding: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding([.top, .bottom], 5)
    }
}

#Preview {
    RecipeDetailEditMobileView(recipe: SampleData.sampleRecipes[0])
}
