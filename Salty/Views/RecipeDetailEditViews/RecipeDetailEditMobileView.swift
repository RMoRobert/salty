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
    @Bindable var viewModel: RecipeDetailEditViewModel
    
    @State private var showingAddTagAlert = false
    @State private var newTagName = ""
    
    init(recipe: Recipe, isNewRecipe: Bool = false, onNewRecipeSaved: ((String) -> Void)? = nil) {
        self.viewModel = RecipeDetailEditViewModel(recipe: recipe, isNewRecipe: isNewRecipe, onNewRecipeSaved: onNewRecipeSaved)
    }
    
    var body: some View {
        List {
            BasicInformationView(viewModel: viewModel)
            IngredientsView(viewModel: viewModel)
            DirectionsView(viewModel: viewModel)
            PreparationTimesView(viewModel: viewModel)
            NotesView(viewModel: viewModel)
            TagsView(viewModel: viewModel, showingAddTagAlert: $showingAddTagAlert, newTagName: $newTagName)
            NutritionView(viewModel: viewModel)
            ImageView(viewModel: viewModel)
        }
#if !os(macOS)
        .environment(\.editMode, .constant(.active))
        .navigationTitle(viewModel.isNewRecipe ? "New Recipe" : "Edit Recipe")
        .navigationBarTitleDisplayMode(.inline)
#endif
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel", role: .cancel) {
                    if viewModel.hasUnsavedChanges {
                        viewModel.showingCancelAlert = true
                    } else {
                        dismiss()
                    }
                }
            }
            ToolbarItem(placement: .primaryAction) {
                
                Button("Save") {
                    viewModel.saveRecipe()
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
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
                    withAnimation {
                        viewModel.addTag(newTagName.trimmingCharacters(in: .whitespacesAndNewlines))
                    }
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
                CategoryEditView(recipe: $viewModel.recipe, selectedCategoryIDs: $viewModel.selectedCategoryIDs)
                    .navigationTitle("Select Categories")
#if !os(macOS)
                    .navigationBarTitleDisplayMode(.inline)
#endif
            }
        }
        
        .sheet(isPresented: $viewModel.showingNutritionEditSheet) {
            NutritionEditView(recipe: $viewModel.recipe)
        }
        .sheet(isPresented: $viewModel.showingScanTextSheet) {
            ScanTextForRecipeView(viewModel: viewModel, initialTarget: viewModel.scanTextTarget)
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
    
    
    // MARK: - Basic Information Section
    struct BasicInformationView: View {
        @Bindable var viewModel: RecipeDetailEditViewModel
        
        var body: some View {
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
                HStack {
                    Picker("Course", selection: $viewModel.recipe.courseId) {
                        Text("(none)")
                            .tag(nil as String?)
                            .foregroundStyle(.secondary)
                        ForEach(viewModel.allCourses) { course in
                            Text(course.name)
                                .tag(course.id as String?)
                        }
                    }
                    .pickerStyle(.menu)
                }
                
                HStack {
                    Text("Categories")
                    Spacer()
                    Button(action: {
                        viewModel.showingEditCategoriesSheet.toggle()
                    }) {
                        Text(viewModel.hasCategories ? viewModel.sortedCategories.joined(separator: ", ") : "Select Categories…")
                            .lineLimit(1)
                            .truncationMode(.tail)
                            .frame(maxWidth: 400, alignment: .trailing)
                    }
                }
            }
            Section {
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
                
            }
            Section {
                TextField("Introduction", text: $viewModel.recipe.introduction, axis: .vertical)
                    .lineLimit(5...10)
            }
        }
    }
    
    // MARK: - Ingredients Section
    struct IngredientsView: View {
        @Bindable var viewModel: RecipeDetailEditViewModel
        
        var body: some View {
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
                            Label("Add Heading", systemImage: "folder.badge.plus")
                        }
                        
                        Button(action: {
                            viewModel.showingBulkEditIngredientsSheet.toggle()
                        }) {
                            Label("Edit as Text (Bulk Edit)", systemImage: "text.page")
                        }
                        
                        Button(action: {
                            viewModel.scanTextTarget = .ingredients
                            viewModel.showingScanTextSheet.toggle()
                        }) {
                            Label("Scan Text", systemImage: "text.viewfinder")
                        }
                    } label: {
                        Label("More", systemImage: "ellipsis")
                            .modifier(EllipsisLabelPadding())
                    }
                    .modifier(EllipsisButtonModifier())
                }
            }
        }
    }
    
    // MARK: - Directions Section
    struct DirectionsView: View {
        @Bindable var viewModel: RecipeDetailEditViewModel
        
        var body: some View {
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
                            Label("Add Heading", systemImage: "folder.badge.plus")
                        }
                        
                        Button(action: {
                            viewModel.showingBulkEditDirectionsSheet.toggle()
                        }) {
                            Label("Edit as Text (Bulk Edit)", systemImage: "text.page")
                        }
                        
                        Button(action: {
                            viewModel.scanTextTarget = .directions
                            viewModel.showingScanTextSheet.toggle()
                        }) {
                            Label("Scan Text", systemImage: "text.viewfinder")
                        }
                    } label: {
                        Label("More", systemImage: "ellipsis")
                            .modifier(EllipsisLabelPadding())
                    }
                    .modifier(EllipsisButtonModifier())
                }
            }
        }
    }
    
    // MARK: - Preparation Time Section
    struct PreparationTimesView: View {
        @Bindable var viewModel: RecipeDetailEditViewModel
        
        var body: some View {
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
        }
    }
    
    // MARK: - Notes Section
    struct NotesView: View {
        @Bindable var viewModel: RecipeDetailEditViewModel
        
        var body: some View {
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
        }
    }
    
    // MARK: - Tags Section
    struct TagsView: View {
        @Bindable var viewModel: RecipeDetailEditViewModel
        @Binding var showingAddTagAlert: Bool
        @Binding var newTagName: String
        
        var body: some View {
            Section("Tags") {
                if viewModel.hasTags {
                    HFlow(itemSpacing: 8, rowSpacing: 4) {
                        ForEach(viewModel.sortedTags, id: \.self) { tag in
                            Button(action: {
                                withAnimation {
                                    viewModel.removeTag(tag)
                                }
                            }) {
                                Label(tag, systemImage: "minus.circle")
                            }
                            .buttonStyle(.bordered)
                            .foregroundStyle(.primary)
                            .backgroundStyle(.secondary)
                            .controlSize(.mini)
                            .accessibilityHint("Remove tag \(tag)")
                            .transition(.asymmetric(
                                insertion: .scale.combined(with: .opacity),
                                removal: .scale.combined(with: .opacity)
                            ))
                        }
                    }
                    .animation(.easeInOut(duration: 0.3), value: viewModel.sortedTags)
                }
                Button(action: {
                    newTagName = ""
                    showingAddTagAlert = true
                }) {
                    Label("Add Tag", systemImage: "plus.circle.fill")
                }
                .labelStyle(.titleAndIcon)
            }
        }
    }
    
    // MARK: - Nutrition Section
    struct NutritionView: View {
        @Bindable var viewModel: RecipeDetailEditViewModel
        
        var body: some View {
            Section("Nutrition Information") {
                Group {
                    if let nutritionSummary = viewModel.nutritionSummary {
                        Text(nutritionSummary)
                            .font(.callout)
                            .padding(.vertical, 8)
                        Button("Edit…") {
                            viewModel.showingNutritionEditSheet.toggle()
                        }
                    } else {
                        Button("Add Nutrition Info", systemImage: "plus.circle.fill") {
                            viewModel.showingNutritionEditSheet.toggle()
                        }
                        .labelStyle(.titleAndIcon)
                    }
                }
            }
        }
    }
    
    // MARK: - Photo Section
    struct ImageView: View {
        @Bindable var viewModel: RecipeDetailEditViewModel
        
        var body: some View {
            Section("Photo") {
                RecipeImageEditView(recipe: $viewModel.recipe, imageFrameSize: 100)
            }
        }
    }
    
    // MARK: - Helper Modifiers
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
}

#Preview {
    RecipeDetailEditMobileView(recipe: SampleData.sampleRecipes[0])
}
