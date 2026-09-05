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
import SaltyCore

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
            VariationsView(viewModel: viewModel)
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
                    Task {
                        // Only dismiss if the save actually succeeded; otherwise the
                        // view model presents an error alert.
                        if await viewModel.saveRecipe() {
                            dismiss()
                        }
                    }
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .alert("Couldn't Save Recipe", isPresented: $viewModel.showingSaveErrorAlert) {
            Button("OK", role: .cancel) { }
        } message: {
            Text(viewModel.saveErrorMessage ?? "An unknown error occurred. Please try again.")
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
                let trimmed = newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    newTagName = ""
                    Task { await viewModel.addTag(trimmed) }
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
        
        /// "Servings" until one is set, then a correctly singular or plural count.
        private var servingsLabel: String {
            guard let servings = viewModel.recipe.servings else { return "Servings" }
            return servings == 1 ? "1 serving" : "\(servings) servings"
        }
        
        var body: some View {
            Section("Basic Information") {
                TextField("Name", text: $viewModel.recipe.name)
                TextField("Source", text: $viewModel.recipe.source)
                TextField("Source Details", text: $viewModel.recipe.sourceDetails)
                Stepper(servingsLabel,
                        value: Binding(
                            get: { viewModel.recipe.servings ?? 0 },
                            set: { viewModel.recipe.servings = $0 == 0 ? nil : $0 }
                        ),
                        in: 0...2000)
                .foregroundStyle(viewModel.recipe.servings != nil ? .primary : .secondary)
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
                    Button {
                        viewModel.showingEditCategoriesSheet.toggle()
                    } label: {
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
        @FocusState private var focusedIngredientID: String?
        
        var body: some View {
            Section("Ingredients") {
                ForEach($viewModel.recipe.ingredients) { $ingredient in
                    let placeholderText = ingredient.isHeading ? "Heading Name" : (ingredient.isMain ? "Main Ingredient Name" : "Ingredient Name")
                    HStack {
                        // `.headline` already carries the weight a heading needs.
                        TextField(placeholderText, text: $ingredient.text)
                            .font(ingredient.isHeading ? .headline : .body)
                            .focused($focusedIngredientID, equals: ingredient.id)
                        Group {
                            if ingredient.isMain {
                                Image(systemName: "medal")
                                    .foregroundStyle(.blue)
                            }
                            else {
                                EmptyView()
                            }
                        }
                    }
                }
                .onDelete { indexSet in
                    viewModel.recipe.ingredients.remove(atOffsets: indexSet)
                }
                .onMove { from, to in
                    viewModel.recipe.ingredients.move(fromOffsets: from, toOffset: to)
                }
                
                HStack {
                    Button("Add Ingredient", systemImage: "plus.circle.fill") {
                        add(.emptyRow())
                    }
                    .labelStyle(.titleAndIcon)
                    
                    Spacer()
                    Menu {
                        Button("Add Heading", systemImage: "folder.badge.plus") {
                            add(.emptyRow(isHeading: true))
                        }
                        
                        Button {
                            add(.emptyRow(isHeading: false, isMain: true))
                        } label: {
                            // A bundled image rather than a symbol, so this one keeps the Label form.
                            Label {
                                Text("Add Main Ingredient")
                            } icon: {
                                Image("recipe-new-main-ingredient-image")
                            }
                        }
                        
                        Button("Edit as Text (Bulk Edit)", systemImage: "text.page") {
                            viewModel.showingBulkEditIngredientsSheet.toggle()
                        }
                        
                        Button("Scan Text", systemImage: "text.viewfinder") {
                            viewModel.scanTextTarget = .ingredients
                            viewModel.showingScanTextSheet.toggle()
                        }
                    } label: {
                        Label("More", systemImage: "ellipsis")
                            .modifier(EllipsisLabelPadding())
                    }
                    .modifier(EllipsisButtonModifier())
                }
            }
        }
        
        /// Appends the row and puts the keyboard in it, so adding several in a row doesn't mean
        /// tapping into each new field first.
        private func add(_ ingredient: Ingredient) {
            let id = RecipeItemListEditor.append(ingredient, to: &viewModel.recipe.ingredients)
            RecipeRowFocus.focus(id, in: $focusedIngredientID)
        }
    }
    
    // MARK: - Directions Section
    struct DirectionsView: View {
        @Bindable var viewModel: RecipeDetailEditViewModel
        @FocusState private var focusedDirectionID: String?
        
        var body: some View {
            Section("Directions") {
                ForEach($viewModel.recipe.directions) { $direction in
                    HStack(alignment: .firstTextBaseline) {
                        // Numbered the way the desktop editor and the printed recipe number them:
                        // headings don't take a number and don't advance the count.
                        if let stepNumber = RecipeItemListEditor.stepNumber(
                            forDirectionWith: direction.id,
                            in: viewModel.recipe.directions
                        ) {
                            Text("\(stepNumber).")
                                .foregroundStyle(.secondary)
                        }
                        
                        // `.headline` already carries the weight a heading needs.
                        TextField(
                            direction.isHeadingRow ? "Heading Name" : "Direction Text",
                            text: $direction.text,
                            axis: .vertical
                        )
                        .font(direction.isHeadingRow ? .headline : .body)
                        // Grows with the step rather than truncating it, but starts at one line so a
                        // recipe with a dozen short steps doesn't turn into a wall of empty rows.
                        // The ceiling is high enough that a real step doesn't clip -- 8 wasn't, and a
                        // truncated row is the thing this is meant to fix -- while still bounding a
                        // pathologically long one. The macOS editor caps at 13 for the same reason.
                        .lineLimit(direction.isHeadingRow ? 1...2 : 1...15)
                        .focused($focusedDirectionID, equals: direction.id)
                    }
                }
                .onDelete { indexSet in
                    viewModel.recipe.directions.remove(atOffsets: indexSet)
                }
                .onMove { from, to in
                    viewModel.recipe.directions.move(fromOffsets: from, toOffset: to)
                }
                HStack {
                    Button("Add Step", systemImage: "plus.circle.fill") {
                        add(.emptyRow())
                    }
                    .labelStyle(.titleAndIcon)
                    
                    Spacer()
                    
                    Menu {
                        Button("Add Heading", systemImage: "folder.badge.plus") {
                            add(.emptyRow(isHeading: true))
                        }
                        
                        Button("Edit as Text (Bulk Edit)", systemImage: "text.page") {
                            viewModel.showingBulkEditDirectionsSheet.toggle()
                        }
                        
                        Button("Scan Text", systemImage: "text.viewfinder") {
                            viewModel.scanTextTarget = .directions
                            viewModel.showingScanTextSheet.toggle()
                        }
                    } label: {
                        Label("More", systemImage: "ellipsis")
                            .modifier(EllipsisLabelPadding())
                    }
                    .modifier(EllipsisButtonModifier())
                }
            }
        }
        
        /// Appends the row and puts the keyboard in it.
        private func add(_ direction: Direction) {
            let id = RecipeItemListEditor.append(direction, to: &viewModel.recipe.directions)
            RecipeRowFocus.focus(id, in: $focusedDirectionID)
        }
    }
    
    // MARK: - Preparation Time Section
    struct PreparationTimesView: View {
        @Bindable var viewModel: RecipeDetailEditViewModel
        @FocusState private var focusedPreparationTimeID: String?
        
        var body: some View {
            Section("Preparation Time") {
                ForEach($viewModel.recipe.preparationTimes) { $preparationTime in
                    HStack {
                        TextField("Type (e.g., \"Bake\")", text: $preparationTime.type)
                            .font(.headline)
                            .focused($focusedPreparationTimeID, equals: preparationTime.id)
                        TextField("Time (e.g., \"30 minutes\")", text: $preparationTime.timeString)
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
                    Button("Add Time", systemImage: "plus.circle.fill") {
                        let id = RecipeItemListEditor.append(.emptyRow(), to: &viewModel.recipe.preparationTimes)
                        RecipeRowFocus.focus(id, in: $focusedPreparationTimeID)
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
        @FocusState private var focusedNoteID: String?
        
        var body: some View {
            Section("Notes") {
                ForEach($viewModel.recipe.notes) { $note in
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Note title", text: $note.title)
                            .font(.headline)
                            .focused($focusedNoteID, equals: note.id)
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
                    Button("Add Note", systemImage: "plus.circle.fill") {
                        let id = RecipeItemListEditor.append(.emptyRow(), to: &viewModel.recipe.notes)
                        RecipeRowFocus.focus(id, in: $focusedNoteID)
                    }
                    .labelStyle(.titleAndIcon)
                    
                    Spacer()
                }
            }
        }
    }
    
    // MARK: - Variations Section
    struct VariationsView: View {
        @Bindable var viewModel: RecipeDetailEditViewModel
        @FocusState private var focusedVariationID: String?
        
        var body: some View {
            Section("Variations") {
                ForEach($viewModel.recipe.variations) { $variation in
                    VStack(alignment: .leading, spacing: 8) {
                        TextField("Variation name", text: $variation.variationName)
                            .font(.headline)
                            .focused($focusedVariationID, equals: variation.id)
                        TextField("Variation text", text: $variation.text, axis: .vertical)
                            .font(.body)
                            .lineLimit(3...6)
                    }
                }
                .onDelete { indexSet in
                    viewModel.recipe.variations.remove(atOffsets: indexSet)
                }
                .onMove { from, to in
                    viewModel.recipe.variations.move(fromOffsets: from, toOffset: to)
                }
                
                HStack {
                    Button("Add Variation", systemImage: "plus.circle.fill") {
                        let id = RecipeItemListEditor.append(.emptyRow(), to: &viewModel.recipe.variations)
                        RecipeRowFocus.focus(id, in: $focusedVariationID)
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
                            Button(tag, systemImage: "minus.circle") {
                                Task { await viewModel.removeTag(tag) }
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
                Button("Add Tag", systemImage: "plus.circle.fill") {
                    newTagName = ""
                    showingAddTagAlert = true
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
                RecipeImageEditView(recipe: $viewModel.recipe, pendingImage: $viewModel.pendingImage, imageFrameSize: 100)
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
