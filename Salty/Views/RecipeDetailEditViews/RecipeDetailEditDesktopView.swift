
//
//  RecipeDetailView.swift
//  Salty
//
//  Created by Robert on 10/21/22, forked from combined view on 7/9/25
//
//  This view is geard towards macOS; see iOS view for mobile-friendly
//

#if os(macOS)

import SwiftUI
import Flow

struct RecipeDetailEditDesktopView: View {
    @Environment(\.dismiss) var dismiss
    @State private var viewModel: RecipeDetailEditViewModel
    @State private var showingAddTagAlert = false
    @State private var newTagName = ""
    
    init(recipe: Recipe, isNewRecipe: Bool = false, onNewRecipeSaved: ((String) -> Void)? = nil) {
        self._viewModel = State(initialValue: RecipeDetailEditViewModel(recipe: recipe, isNewRecipe: isNewRecipe, onNewRecipeSaved: onNewRecipeSaved))
    }
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                BasicInformationView(viewModel: $viewModel)
                IntroductionView(viewModel: $viewModel)
                IngredientsView(viewModel: $viewModel)
                DirectionsView(viewModel: $viewModel)
                PreparationTimesView(viewModel: $viewModel)
                NotesView(viewModel: $viewModel)
                TagsView(viewModel: $viewModel, showingAddTagAlert: $showingAddTagAlert, newTagName: $newTagName)
                NutritionView(viewModel: $viewModel)
                PhotoView(viewModel: $viewModel)
            }
            .padding()
        }
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
        .alert("Add Tag", isPresented: $showingAddTagAlert) {
            TextField("Tag name", text: $newTagName)
            Button("Cancel", role: .cancel) {
                newTagName = ""
            }
            Button("Add") {
                addNewTag()
            }
            .disabled(newTagName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        } message: {
            Text("Enter a name for the new tag")
        }
        .sheet(isPresented: $viewModel.showingScanTextSheet) {
            ScanTextForRecipeView(viewModel: $viewModel, initialTarget: viewModel.scanTextTarget)
        }
        .interactiveDismissDisabled(viewModel.hasUnsavedChanges)
        .onKeyPress(.escape) {
            if viewModel.hasUnsavedChanges {
                viewModel.showingCancelAlert = true
                return .handled
            }
            return .ignored
        }
        .frame(minWidth: 600, minHeight: 500)
    }
    
    // MARK: - Helper Methods
    private func addNewTag() {
        let trimmedTag = newTagName.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedTag.isEmpty else { 
            newTagName = ""
            return 
        }
        withAnimation {
            viewModel.addTag(trimmedTag)
        }
        newTagName = ""
    }
    
    
    // MARK: - Basic Information View
    struct BasicInformationView: View {
        @Binding var viewModel: RecipeDetailEditViewModel
        
        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                Form {
                    TextField("Name:", text: $viewModel.recipe.name)
                    TextField("Source:", text: $viewModel.recipe.source)
                    TextField("Source Details:", text: $viewModel.recipe.sourceDetails)
                    TextField("Servings:", text: Binding(
                        get: { viewModel.recipe.servings?.description ?? "" },
                        set: { 
                            let filtered = $0.filter { $0.isNumber }
                            viewModel.recipe.servings = filtered.isEmpty ? nil : Int(filtered)
                        }
                    ))
                    TextField("Yield:", text: $viewModel.recipe.yield)
                    Picker("Course:", selection: Binding(
                        get: { viewModel.recipe.courseId },
                        set: { viewModel.recipe.courseId = $0 }
                    )) {
                        Text("(No Course)")
                            .tag(nil as String?)
                        
                        ForEach(viewModel.courses) { course in
                            Text(course.name)
                                .tag(course.id as String?)        
                        }
                    }
                    .pickerStyle(.menu)
                    HStack {
                        Toggle("Favorite", isOn: $viewModel.recipe.isFavorite)
                        Spacer()
                        Toggle("Want to make", isOn: $viewModel.recipe.wantToMake)
                        Spacer()
                        Button("Edit Categories") {
                            viewModel.showingEditCategoriesSheet.toggle()
                        }
                        .popover(isPresented: $viewModel.showingEditCategoriesSheet) {
                            CategoryEditView(recipe: $viewModel.recipe)
                        }
                    }
                }
                VStack {
                    HStack(alignment: .firstTextBaseline, spacing: 16) {
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Rating:")
                                .frame(width: 80, alignment: .leading)
                            RatingEditView(recipe: $viewModel.recipe)
                                .frame(maxWidth: 250)
                        }
                        Spacer()
                        VStack(alignment: .leading, spacing: 8) {
                            Text("Difficulty:")
                                .frame(width: 80, alignment: .leading)
                            DifficultyEditView(recipe: $viewModel.recipe)
                                .frame(maxWidth: 250)
                        }
                    }
                }
            }
            .padding(.bottom, 8)
        }
    }
    
    // MARK: - Introduction View
    struct IntroductionView: View {
        @Binding var viewModel: RecipeDetailEditViewModel
        
        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Introduction:")
                        .modifier(TitleDesktopEditorStyle())
                    Spacer()
                    Menu {
                        Button("Scan Text") {
                            viewModel.scanTextTarget = .introduction
                            viewModel.showingScanTextSheet.toggle()
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .controlSize(.large)
                    }
                    .buttonStyle(.plain)
                }
                
                VStack(spacing: 12) {
                    TextField("Introduction", text: $viewModel.recipe.introduction, axis: .vertical)
                        .lineLimit(5...10)
                        .labelStyle(.titleOnly)
                }
            }
            .padding(.bottom, 8)
        }
    }
    
    // MARK: - Ingredients View
    struct IngredientsView: View {
        @Binding var viewModel: RecipeDetailEditViewModel
        
        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Ingredients:")
                        .modifier(TitleDesktopEditorStyle())
                    Spacer()
                    Button("Edit Ingredients") {
                        viewModel.showingEditIngredientsSheet.toggle()
                    }
                    .buttonStyle(.bordered)
                    
                    Menu {
                        Button("Edit as Text (Bulk Edit)") {
                            viewModel.showingBulkEditIngredientsSheet.toggle()
                        }
                        
                        Button("Scan Text") {
                            viewModel.scanTextTarget = .ingredients
                            viewModel.showingScanTextSheet.toggle()
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .controlSize(.large)
                    }
                    .buttonStyle(.plain)
                }
                if viewModel.recipe.ingredients.isEmpty {
                    Text("No ingredients added")
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                } else {
                    VStack(alignment: .leading, spacing: 3) {
                        ForEach(viewModel.recipe.ingredients) { ingredient in
                            if ingredient.isHeading {
                                Text(ingredient.text)
                                    .font(.callout)
                                    .fontWeight(.semibold)
                                    .padding(.top, 2)
                            } else {
                                Text(ingredient.text)
                                    .font(.body)
                            }
                        }
                    }
                }
            }
            .sheet(isPresented: $viewModel.showingEditIngredientsSheet) {
                IngredientsEditView(recipe: $viewModel.recipe)
            }
            .sheet(isPresented: $viewModel.showingBulkEditIngredientsSheet) {
                RecipeIngredientsBulkEditView(recipe: $viewModel.recipe)
            }
            .padding(.bottom, 8)
        }
    }
    
    // MARK: - Directions View
    struct DirectionsView: View {
        @Binding var viewModel: RecipeDetailEditViewModel
        
        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Directions:")
                        .modifier(TitleDesktopEditorStyle())
                    Spacer()
                    Button("Edit Directions") {
                        viewModel.showingEditDirectionsSheet.toggle()
                    }
                    .buttonStyle(.bordered)
                    
                    Menu {
                        Button("Edit as Text (Bulk Edit)") {
                            viewModel.showingBulkEditDirectionsSheet.toggle()
                        }
                        Button("Scan Text") {
                            viewModel.scanTextTarget = .directions
                            viewModel.showingScanTextSheet.toggle()
                        }
                    } label: {
                        Image(systemName: "ellipsis.circle")
                            .controlSize(.large)
                    }
                    .buttonStyle(.plain)
                }
                
                if viewModel.recipe.directions.isEmpty {
                    Text("No directions added")
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                } else {
                    VStack(alignment: .leading, spacing: 8) {
                        ForEach(Array(viewModel.recipe.directions.enumerated()), id: \.element.id) { index, direction in
                            HStack(alignment: .top, spacing: 12) {
                                if direction.isHeading != true {
                                    Text("\(viewModel.recipe.directions.prefix(index + 1).filter { $0.isHeading != true }.count).")
                                        .font(.body)
                                        .fontWeight(.medium)
                                        .foregroundColor(.secondary)
                                        .frame(width: 24, alignment: .leading)
                                } else {
                                    Spacer()
                                        .frame(width: 24)
                                }
                                VStack(alignment: .leading, spacing: 4) {
                                    if direction.isHeading == true {
                                        Text(direction.text)
                                            .font(.callout)
                                            .fontWeight(.semibold)
                                    } else {
                                        Text(direction.text)
                                            .font(.body)
                                    }
                                }
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
            .sheet(isPresented: $viewModel.showingEditDirectionsSheet) {
                DirectionsEditView(recipe: $viewModel.recipe)
            }
            .sheet(isPresented: $viewModel.showingBulkEditDirectionsSheet) {
                RecipeDirectionsBulkEditView(recipe: $viewModel.recipe)
            }
            .padding(.bottom, 8)
        }
    }
    
    // MARK: - Preparation Times View
    struct PreparationTimesView: View {
        @Binding var viewModel: RecipeDetailEditViewModel
        
        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Preparation Times:")
                        .modifier(TitleDesktopEditorStyle())
                    Spacer()
                    Button("Edit Times") {
                        viewModel.showingEditPreparationTimes.toggle()
                    }
                    .buttonStyle(.bordered)
                }
                
                if viewModel.recipe.preparationTimes.isEmpty {
                    Text("No preparation times added")
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                } else {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(viewModel.recipe.preparationTimes) { preparationTime in
                            HStack {
                                Text("\(preparationTime.type):")
                                    .fontWeight(.semibold)
                                Text("\(preparationTime.timeString)")
                            }
                        }
                    }
                }
            }
            .sheet(isPresented: $viewModel.showingEditPreparationTimes) {
                PreparationTimesEditView(recipe: $viewModel.recipe)
            }
            .padding(.bottom, 8)
        }
    }
    
    // MARK: - Notes View
    struct NotesView: View {
        @Binding var viewModel: RecipeDetailEditViewModel
        
        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Notes:")
                        .modifier(TitleDesktopEditorStyle())
                    Spacer()
                    Button("Edit Notes") {
                        viewModel.showingEditNotesSheet.toggle()
                    }
                    .buttonStyle(.bordered)
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
            .sheet(isPresented: $viewModel.showingEditNotesSheet) {
                NotesEditView(recipe: $viewModel.recipe)
            }
        }
    }
    
    // MARK: - Tags View
    struct TagsView: View {
        @Binding var viewModel: RecipeDetailEditViewModel
        @Binding var showingAddTagAlert: Bool
        @Binding var newTagName: String
        
        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Tags:")
                        .modifier(TitleDesktopEditorStyle())
                    Spacer()
                    Button("Add Tag") {
                        newTagName = ""
                        showingAddTagAlert = true
                    }
                    .buttonStyle(.bordered)
                }
                
                HFlow(itemSpacing: 8, rowSpacing: 4) {
                    ForEach(viewModel.sortedTags, id: \.self) { tag in
                        Button(action: {
                            withAnimation {
                                viewModel.removeTag(tag)
                            }
                        }) {
                            Label(tag, systemImage: "minus.circle")
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(.quaternary, in: Capsule())
                                .foregroundColor(.primary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityHint("Remove tag \(tag)")
                        .transition(.asymmetric(
                            insertion: .scale.combined(with: .opacity),
                            removal: .scale.combined(with: .opacity)
                        ))
                    }
                }
                .animation(.easeInOut(duration: 0.3), value: viewModel.sortedTags)
            }
        }
    }
    
    // MARK: - Nutrition View
    struct NutritionView: View {
        @Binding var viewModel: RecipeDetailEditViewModel
        
        var body: some View {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text("Nutrition Information:")
                        .modifier(TitleDesktopEditorStyle())
                    Spacer()
                    Button("Edit Nutrition Info") {
                        viewModel.showingNutritionEditSheet.toggle()
                    }
                    .buttonStyle(.bordered)
                }
                
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
                        Text("No nutrition values entered")
                            .foregroundStyle(.secondary)
                            .padding(.vertical, 8)
                    } else {
                        Text(parts.joined(separator: ", "))
                            .padding(.vertical, 8)
                    }
                } else {
                    Text("No nutrition information added")
                        .foregroundStyle(.secondary)
                        .padding(.vertical, 8)
                }
            }
            .sheet(isPresented: $viewModel.showingNutritionEditSheet) {
                NutritionEditView(recipe: $viewModel.recipe)
            }
        }
    }
    
    // MARK: - Photo View
    struct PhotoView: View {
        @Binding var viewModel: RecipeDetailEditViewModel
        
        var body: some View {
            VStack(alignment: .leading, spacing: 16) {
                Text("Photo:")
                    .modifier(TitleDesktopEditorStyle())
                RecipeImageEditView(recipe: $viewModel.recipe, imageFrameSize: 150)
            }
        }
    }
    
    // MARK: - Title Style Modifier
    struct TitleDesktopEditorStyle: ViewModifier {
        func body(content: Content) -> some View {
            content
                .font(.title2)
                .fontWeight(.semibold)
        }
    }
}

#Preview {
    RecipeDetailEditDesktopView(recipe: SampleData.sampleRecipes[0], isNewRecipe: false, onNewRecipeSaved: nil)
}

#endif
