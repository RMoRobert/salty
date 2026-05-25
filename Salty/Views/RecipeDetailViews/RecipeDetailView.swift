//
//  RecipeDetailView.swift
//  Salty
//
//  Created by Robert on 6/20/23.
//

import Foundation
import SwiftUI
import Flow

struct RecipeDetailView: View {
    @State private var viewModel: RecipeDetailViewModel
    @Environment(\.openWindow) private var openWindow
    
    init(recipe: Recipe, onScaledRecipeSaved: ((String) -> Void)? = nil) {
        self._viewModel = State(initialValue: RecipeDetailViewModel(recipe: recipe, onScaledRecipeSaved: onScaledRecipeSaved))
    }
    
    var body: some View {
        Group {
            if let recipe = viewModel.recipe {
                ScrollView {
                    Group {
                        TitleAndBasicInfoSection(viewModel: viewModel)
                        PrepTimeAndFavoriteEtcSection(recipe: recipe)
                        IntroductionSection(recipe: recipe)
                        AdaptiveStack(verticalAlignment: .top) {
                            IngredientsSection(viewModel: viewModel, recipe: recipe)
                            DirectionsSection(viewModel: viewModel, recipe: recipe)
                        }
                        NotesSection(recipe: recipe)
                            .padding(.top, 2)
                        VariationsSection(recipe: recipe)
                            .padding(.top, 2)
                        TagsSection(viewModel: viewModel)
                            .padding(.top, 2)
                    }
                    .padding()
                }
                .fontDesign(.rounded)
                .background(LinearGradient(
                    colors: [Color.recipeDetailPageBackgroundA, Color.recipeDetailPageBackgroundB],
                    startPoint: .top, endPoint: .bottom
                ))
                .foregroundStyle(Color.recipeDetailBoxForeground)
                .textSelection(.enabled)
                .sheet(isPresented: $viewModel.showingFullImage) {
                    RecipeFullImageView(recipe: recipe)
                        .frame(minWidth: 300, idealWidth: 800, minHeight: 450, idealHeight: 900)
                }

                #if !os(macOS)
                .navigationTitle(viewModel.shouldShowNavigationTitle ? recipe.name : "")
                #else
                .navigationTitle(recipe.name)  // do I need this on macOS? Not displayed but doesn't seem to hurt
                #endif
                .toolbarTitleDisplayMode(.inline)
            } else {
                ProgressView("Loading recipe...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

// MARK: - Private Subviews

private struct TitleAndBasicInfoSection: View {
    @Bindable var viewModel: RecipeDetailViewModel
    
    var body: some View {
        AdaptiveStack {
            VStack(spacing: 4) {
                HStack {
                    Text(viewModel.recipe?.name ?? "")
                        .font(.title)
                        .fontWeight(.bold)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(alignment: .top)
#if !os(macOS)
                        .background(
                            GeometryReader { titleGeometry in
                                Color.clear
                                    .onAppear {
                                        let titleFrame = titleGeometry.frame(in: .global)
                                        let buffer: CGFloat = 90
                                        viewModel.isTitleVisible = titleFrame.maxY > buffer
                                    }
                                    .onChange(of: titleGeometry.frame(in: .global)) { _, newFrame in
                                        let buffer: CGFloat = 90
                                        viewModel.isTitleVisible = newFrame.maxY > buffer
                                    }
                                    .accessibilityHidden(true)
                            }
                        )
#endif
                }
                Spacer()
                if let recipe = viewModel.recipe, !recipe.source.isEmpty {
                    HStack {
                        Image(systemName: "text.book.closed")
                        Text(recipe.source)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Source: \(recipe.source)")
                }
                if let recipe = viewModel.recipe, !recipe.sourceDetails.trimmingCharacters(in: .whitespaces).isEmpty {
                    let sourceDetails = recipe.sourceDetails.trimmingCharacters(in: .whitespaces)
                    if let url = URL(string: sourceDetails),
                       let _ = url.scheme?.lowercased().starts(with: "http") {
                        Link(destination: url) {
                            Text(sourceDetails)
                                .lineLimit(2)
                                .truncationMode(.middle)
                                .foregroundStyle(Color.blue)
                        }
                    }
                    else {
                        Text(recipe.sourceDetails)
                    }
                }
                Spacer()
                HFlow(itemSpacing: 12) {
                    if let courseName = viewModel.courseName {
                        HStack {
                            Image(systemName: "fork.knife.circle")
                            Text(courseName)
                        }
                        .modifier(CapsuleBackgroundModifier())
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Course: \(courseName)")
                    }
                    if let recipe = viewModel.recipe, !recipe.yield.isEmpty {
                        HStack {
                            Image(systemName: "circle.grid.2x2")
                            Text(recipe.yield)
                        }
                        .modifier(CapsuleBackgroundModifier())
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Yield: \(recipe.yield)")
                    }
                    if let recipe = viewModel.recipe, let servings = recipe.servings, servings > 0 {
                        HStack {
                            Image(systemName: "person.2")
                            Text(servings.description)
                        }
                        .modifier(CapsuleBackgroundModifier())
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Servings: \(servings)")
                    }
                }
            }
            .padding()
            if let recipe = viewModel.recipe, recipe.imageFilename != nil {
                RecipeImageView(recipe: recipe)
                    .shadow(radius: 2)
                    .padding()
                    .onTapGesture {
                        viewModel.showFullImage()
                    }
            }
        }
        .padding([.top], 8)
        .modifier(RecipeSectionBoxModifier())
    }
}

private struct PrepTimeAndFavoriteEtcSection: View {
    let recipe: Recipe
    var body: some View {
        VStack {
            if (recipe.isFavorite || recipe.wantToMake) {
                HFlow(itemSpacing: 24, rowSpacing: 12) {
                    if (recipe.isFavorite) {
                        HStack {
                            Image(systemName: "heart.fill")
                                .foregroundColor(.red)
                                .modifier(IconShadowModifier())
                            Text("Favorite")
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Marked as Favorite")
                    }
                    if (recipe.wantToMake) {
                        HStack {
                            Image(systemName: "checkmark.diamond")
                                .foregroundColor(Color.green.opacity(0.8))
                                .modifier(IconShadowModifier())
                            Text("Want to Make")
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Marked as Want to Make")
                    }
                }
                .padding(.horizontal)
                .opacity((recipe.isFavorite || recipe.wantToMake) ? 1 : 0)
                .allowsHitTesting(recipe.isFavorite || recipe.wantToMake)
            }
            if recipe.preparationTimes.count > 0 {
                HFlow(itemSpacing: 12, rowSpacing: 8) {
                    ForEach(recipe.preparationTimes) { prepTime in
                        HStack {
                            Image(systemName: "clock")
                            VStack {
                                Text("\(prepTime.type)")
                                    .font(.caption)
                                Text("\(prepTime.timeString)")
                            }
                            .accessibilityHidden(true)
                        }
                        .modifier(CapsuleBackgroundModifier())
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Preparation time: type: \(prepTime.type), duration: \(prepTime.timeString)")
                    }
                }
                .padding(.horizontal)
            }
            HFlow(alignment: .top, itemSpacing: 60, rowSpacing: 30) {
                VStack(spacing: 10) {
                    RatingView(recipe: recipe, showLabel: false)
                }
                VStack(spacing: 10) {
                    DifficultyView(recipe: recipe, showLabel: false)
                }
            }
        }
        .padding(8)
        .modifier(RecipeSectionBoxModifier())
    }
}

private struct IntroductionSection: View {
    let recipe: Recipe
    var body: some View {
        if !recipe.introduction.isEmpty {
            VStack {
                Text(recipe.introduction)
                    .italic()
                    .padding()
            }
        }
        else {
            VStack {}
                .padding(1)
        }
    }
}

private struct IngredientsSection: View {
    @Bindable var viewModel: RecipeDetailViewModel
    let recipe: Recipe
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Ingredients")
                .modifier(TitleStyle())
            ForEach(recipe.ingredients.indices, id: \.self) { index in
                let ingredient = recipe.ingredients[index]
                if ingredient.isHeading {
                    Text(ingredient.text)
                        .font(.callout)
                        .fontWeight(.semibold)
                        .foregroundStyle(.recipeDetailBoxForeground2)
                        .padding(.top, 8)
                        .padding(.bottom, 6)
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•")
                            .foregroundStyle(.recipeDetailBoxForeground)
                            .fontWeight(.bold)
                        let parsed = viewModel.scaledIngredientDisplay(ingredient)
                        if parsed.hasQuantity {
                            (Text(parsed.quantity)
                                .fontWeight(.semibold) +
                             Text(parsed.remainder.isEmpty ? "" : " \(parsed.remainder)")
                                .fontWeight(.regular))
                                .fixedSize(horizontal: false, vertical: true)
                                .foregroundStyle(.recipeDetailBoxForeground)
                                .accessibilityElement(children: .combine)
                        } else {
                            Text(ingredient.text)
                                .fixedSize(horizontal: false, vertical: true)
                                .foregroundStyle(.recipeDetailBoxForeground)
                                .fontWeight(.regular)
                        }
                    }
                    .padding(.bottom, 4)
                }
            }
            if viewModel.isIngredientScaleActive {
                Text("Scaled to \(viewModel.ingredientScalePercentLabel)%")
                    .foregroundStyle(.secondary)
                    .padding(.top, 8)
                    .font(.caption)
            }
            Button("Scale…", systemImage: "slider.horizontal.3") {
                viewModel.isIngredientScalePopoverShowing = true
            }
            #if os(macOS)
            .buttonStyle(.link)
            #else
            .buttonStyle(.plain)
            #endif
            .controlSize(.small)
            .padding(.bottom, 4)
            .padding(.top, 16)
            .popover(isPresented: $viewModel.isIngredientScalePopoverShowing) {
                IngredientScalePopoverContent(viewModel: viewModel)
            }
        }
        .frame(minWidth: 85, maxWidth: 300)
        .modifier(RecipeSectionBoxModifier())
    }
}

private struct IngredientScalePopoverContent: View {
    @Bindable var viewModel: RecipeDetailViewModel
    
    var body: some View {
        VStack(spacing: 12) {
            HStack {
                TextField("Scale by:", value: $viewModel.ingredientScalePercent, format: .number.precision(.fractionLength(2)))
                    .frame(width: 70)
                Text("%")
            }
            .accessibilityElement(children: .combine)
            
            Slider(value: $viewModel.ingredientScalePercent, in: 25...400)
            
            HStack(spacing: 8) {
                IngredientScalePresetButton(
                    title: "Half",
                    accessibilityLabel: "Half recipe",
                    isSelected: viewModel.isIngredientScaleNear(50)
                ) {
                    viewModel.ingredientScalePercent = 50
                }
                IngredientScalePresetButton(
                    title: "Two-Thirds",
                    accessibilityLabel: "Two-thirds recipe",
                    isSelected: viewModel.isIngredientScaleNear(66.67)
                ) {
                    viewModel.ingredientScalePercent = 66.67
                }
                IngredientScalePresetButton(
                    title: "Double",
                    accessibilityLabel: "Double recipe",
                    isSelected: viewModel.isIngredientScaleNear(200)
                ) {
                    viewModel.ingredientScalePercent = 200
                }
            }
            
            Button("Reset") {
                viewModel.resetIngredientScale()
            }
            .frame(maxWidth: .infinity)
            .buttonStyle(.borderless)
            .controlSize(.small)
            .disabled(!viewModel.isIngredientScaleActive)
            
            Button("Save as New Recipe…") {
                viewModel.saveAsScaledRecipe()
            }
            .frame(maxWidth: .infinity)
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(!viewModel.isIngredientScaleActive || viewModel.isSavingScaledRecipe)
            
            if viewModel.isSavingScaledRecipe {
                ProgressView()
                    .controlSize(.small)
            }
        }
        .frame(minWidth: 200, idealWidth: 220)
        .padding()
        .alert(
            "Could Not Save Recipe",
            isPresented: Binding(
                get: { viewModel.scaledRecipeSaveErrorMessage != nil },
                set: { if !$0 { viewModel.scaledRecipeSaveErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) {
                viewModel.scaledRecipeSaveErrorMessage = nil
            }
        } message: {
            Text(viewModel.scaledRecipeSaveErrorMessage ?? "")
        }
    }
}

private struct IngredientScalePresetButton: View {
    let title: String
    let accessibilityLabel: String
    let isSelected: Bool
    let action: () -> Void
    
    var body: some View {
        Group {
            if isSelected {
                Button(action: action) {
                    Text(title)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
            } else {
                Button(action: action) {
                    Text(title)
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)
            }
        }
        .controlSize(.small)
        .accessibilityLabel(accessibilityLabel)
    }
}

private struct DirectionsSection: View {
    @Bindable var viewModel: RecipeDetailViewModel
    let recipe: Recipe
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("Directions")
                .modifier(TitleStyle())
            ForEach(recipe.directions.indices, id: \.self) { index in
                let isHeading = recipe.directions[index].isHeading ?? false
                if isHeading {
                    Text(recipe.directions[index].text)
                        .font(.callout)
                        .fontWeight(.semibold)
                        .foregroundStyle(.recipeDetailBoxForeground2)
                        .padding(.top, 8)
                        .padding(.bottom, 6)
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(recipe.directions.prefix(index + 1).filter { $0.isHeading != true }.count).")
                            .fontWeight(.semibold)
                        Text(recipe.directions[index].text)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.bottom, 4)
                }
            }
            if viewModel.isIngredientScaleActive {
                Text(viewModel.ingredientScaleDirectionsFootnote)
                    .font(.caption)
                    .foregroundStyle(.recipeDetailBoxForeground2)
                    .italic()
                    .padding(.top, 8)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(minWidth: 95, maxWidth: 1000)
        .modifier(RecipeSectionBoxModifier())
    }
}

private struct NotesSection: View {
    let recipe: Recipe
    var body: some View {
        if recipe.notes.count > 0 {
            VStack(alignment: .leading) {
                Text("Notes")
                    .modifier(TitleStyle())
                    .padding(.bottom, 2) // override to reduce space below heading
                ForEach(recipe.notes.indices, id: \.self) { index in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(recipe.notes[index].title)
                            .font(.callout)
                            .fontWeight(.semibold)
                            .foregroundStyle(.recipeDetailBoxForeground2)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(recipe.notes[index].content)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, index == 0 ? 0 : 2) // no top padding for first note
                    .padding(.bottom, 2)
                }
            }
            
            .modifier(RecipeSectionBoxModifier())
            .frame(maxWidth: .infinity)
        }
    }
}

private struct VariationsSection: View {
    let recipe: Recipe
    var body: some View {
        if recipe.variations.count > 0 {
            VStack(alignment: .leading) {
                Text("Variations")
                    .modifier(TitleStyle())
                    .padding(.bottom, 2) // override to reduce space below heading
                ForEach(recipe.variations.indices, id: \.self) { index in
                    VStack(alignment: .leading, spacing: 4) {
                        Text(recipe.variations[index].variationName)
                            .font(.callout)
                            .fontWeight(.semibold)
                            .foregroundStyle(.recipeDetailBoxForeground2)
                            .fixedSize(horizontal: false, vertical: true)
                        Text(recipe.variations[index].text)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.top, index == 0 ? 0 : 2) // no top padding for first variation
                    .padding(.bottom, 2)
                }
            }
            
            .modifier(RecipeSectionBoxModifier())
            .frame(maxWidth: .infinity)
        }
    }
}

private struct TagsSection: View {
    @Bindable var viewModel: RecipeDetailViewModel
    
    var body: some View {
        if !viewModel.recipeTags.isEmpty {
            VStack(alignment: .leading) {
                Text("Tags")
                    .modifier(TitleStyle())
                HFlow(itemSpacing: 8, rowSpacing: 16) {
                    ForEach(viewModel.recipeTags, id: \.id) { tag in
                        Label(tag.name, systemImage: "tag")
                            .padding(.vertical, 4)
                            .padding(.horizontal, 6)
                            .background(Color.recipeDetailPageBackgroundA.opacity(0.66), in: Capsule())
                    }
                }
            }
            .modifier(RecipeSectionBoxModifier())
            .frame(maxWidth: .infinity)
        }
    }
}


// MARK: Modifier Structs

private struct TitleStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.title2)
            .fontWeight(.bold)
            .padding(.top, 8)
            .padding(.bottom, 8)
    }
}

private struct IconShadowModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .shadow(radius: 0.5, x:0.5, y:1)
    }
}

private struct CapsuleBackgroundModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(EdgeInsets(top: 3, leading: 12, bottom: 3, trailing: 12))
            .background(Color.recipeDetailPageBackgroundA.opacity(0.66))
            .clipShape(Capsule())
            .padding(EdgeInsets(top: 1, leading: 4, bottom: 10, trailing: 6))
    }
}


private struct RecipeSectionBoxModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            .padding(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            .background(Color.recipeDetailBoxBackground)
            .foregroundStyle(Color.recipeDetailBoxForeground)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(color: Color.recipeDetailBoxShadow.opacity(0.7), radius: 3, x:1, y:1)
            .padding(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
    }
}



#Preview {
    RecipeDetailView(recipe: SampleData.sampleRecipes[0])
}


