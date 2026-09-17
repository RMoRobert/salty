//
//  RecipeDetailView.swift
//  Salty
//
//  Created by Robert on 6/20/23.
//

import Foundation
import SwiftUI
import Flow
import SaltyCore

struct RecipeDetailView: View {
    @State private var viewModel: RecipeDetailViewModel
    @Environment(\.openWindow) private var openWindow
    @Environment(ChefViewSessionStore.self) private var chefSessionStore
    #if !os(macOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    /// Supplied by the host so this view can place Edit itself. Toolbar content from a host is
    /// collected *before* its child's, so an item declared here always lands outboard of one the
    /// host declares -- the only way to keep Edit on the outer edge with Chef View on other side of it is
    /// for both to be declared here, in that order. Hosts that show `RecipeDetailWebView` instead
    /// keep declaring their own Edit, since this view isn't in the hierarchy at all then.
    private let onEdit: (() -> Void)?

    init(recipe: Recipe, onEdit: (() -> Void)? = nil, onScaledRecipeSaved: ((String) -> Void)? = nil) {
        self.onEdit = onEdit
        self._viewModel = State(initialValue: RecipeDetailViewModel(recipe: recipe, onScaledRecipeSaved: onScaledRecipeSaved))
    }

    /// Whether to break Chef View out of the capsule it would otherwise share with its neighbour.
    ///
    /// Always on macOS, where it would fuse with Edit. On iOS only at regular width, i.e.,
    /// when the host declares the show/hide-list toggle for it to sit beside (at compact width, the
    /// neighbor is the provided Back button, which it already won't fuse with).
    private var showsChefViewSpacer: Bool {
        #if os(macOS)
        true
        #else
        horizontalSizeClass == .regular
        #endif
    }

    /// Where Chef View icon is placed, slight platform differences since bars differ on each.
    ///
    /// On iOS, place in leading, beside the split view's show/hide-list toggle. macOS has
    /// no `.topBarLeading`, and `.navigation` puts it at very leading edge of window
    /// titlebar, where it's not clearly connected to recipe, so put in trailing group instead, but
    /// on trailing edge of "Edit" so "Edit" is more prominent.
    private static var chefViewPlacement: ToolbarItemPlacement {
        #if os(macOS)
        .primaryAction
        #else
        .topBarLeading
        #endif
    }

    /// Chef View is presented from here rather than the split view's root because this view owns the
    /// live ingredient-scale state Chef View needs (which also means every context that hosts a
    /// recipe detail -- e.g., split-view column, macOS recipe window -- gets the entry point for free).
    private func openChefView(recipe: Recipe) {
        #if os(macOS)
        openWindow(
            id: "chef-view-window",
            value: ChefViewLaunch(recipeId: recipe.id, scalePercent: viewModel.ingredientScalePercent)
        )
        #else
        viewModel.isChefViewPresented = true
        #endif
    }

    var body: some View {
        Group {
            if let recipe = viewModel.recipe {
                ScrollView {
                    VStack(spacing: 8) {
                        TitleAndBasicInfoSection(viewModel: viewModel, recipe: recipe)
                        PrepTimeAndRatingsAndMiscSection(recipe: recipe)
                        IntroductionSection(recipe: recipe)
                        IngredientsAndDirectionsSection(viewModel: viewModel, recipe: recipe)
                        NotesSection(recipe: recipe)
                        VariationsSection(recipe: recipe)
                        TagsSection(viewModel: viewModel)
                    }
                    .padding()
                }
                .fontDesign(.rounded)
                .background(LinearGradient(
                    colors: [Color.recipeDetailPageBackgroundA, Color.recipeDetailPageBackgroundB],
                    startPoint: .top, endPoint: .bottom
                ))
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
                .toolbar {
                    // Declare Edit first to get better positioning on macOS (on iOS, have different placements
                    // do doesn't matter):
                    if let onEdit {
                        ToolbarItem(placement: .primaryAction) {
                            Button("Edit", systemImage: "pencil", action: onEdit)
                                .keyboardShortcut("e", modifiers: .command)
                        }
                    }
                    // Avoid single capsule with "full detail view" icon
                    if #available(iOS 26.0, macOS 26.0, *) {
                        if showsChefViewSpacer {
                            ToolbarSpacer(.fixed, placement: Self.chefViewPlacement)
                        }
                    }
                    ToolbarItem(placement: Self.chefViewPlacement) {
                        Button("Chef View", systemImage: "rectangle.stack.badge.play") {
                            openChefView(recipe: recipe)
                        }
                        #if os(macOS)
                        .help("Cook from this recipe in Chef View")
                        #endif
                    }
                }
                // Scene-scoped, so the View > Chef View command reaches the recipe in the frontmost
                // window and nothing else. See ChefViewOpenAction.
                .focusedSceneValue(\.chefViewOpenAction, ChefViewOpenAction { openChefView(recipe: recipe) })
                #if !os(macOS)
                // Full-screen cover on iOS/iPadOS; macOS, opens the window scene above instead.
                .fullScreenCover(isPresented: $viewModel.isChefViewPresented) {
                    ChefView(
                        recipe: recipe,
                        scaleFactor: viewModel.ingredientScaleFactor,
                        sessionStore: chefSessionStore
                    )
                }
                #endif
            } else {
                ProgressView("Loading recipe...")
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
    }
}

// MARK: - Header

/// Title, source, and course/yield/servings chips, centered beside photo when the card
/// is wide enough for both, or above if not
private struct TitleAndBasicInfoSection: View {
    @Bindable var viewModel: RecipeDetailViewModel
    let recipe: Recipe

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                TitleAndBasicInfoText(viewModel: viewModel, recipe: recipe)
                RecipeHeaderImage(viewModel: viewModel, recipe: recipe, size: 150)
            }
            // ViewThatFits measures the *ideal* width, and a paragraph's ideal width is one long
            // line. This makes it side by side only when the card has at least this much room:
            .frame(idealWidth: 520)
            // Both sub-views have own padding, so adding none here:
            VStack(spacing: 0) {
                TitleAndBasicInfoText(viewModel: viewModel, recipe: recipe)
                RecipeHeaderImage(viewModel: viewModel, recipe: recipe, size: 125)
            }
        }
        // These top couple cards are centered and possibly varied width, unlike others that are full width:
        .modifier(RecipeSectionBoxModifier(fillsWidth: false))
    }
}

private struct TitleAndBasicInfoText: View {
    @Bindable var viewModel: RecipeDetailViewModel
    let recipe: Recipe

    var body: some View {
        // Spacers rather than fixed spacing: beside the photo the column is as tall as the photo,
        // and the spacers spread the lines over that height instead of leaving them bunched in the
        // middle. Stacked (no height to fill) they collapse to their minimum.
        VStack(spacing: 4) {
            Text(recipe.name)
                .font(.title)
                .bold()
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)
#if !os(macOS)
                .onGeometryChange(for: CGFloat.self) { proxy in
                    proxy.frame(in: .global).maxY
                } action: { maxY in
                    let buffer: CGFloat = 90
                    viewModel.isTitleVisible = maxY > buffer
                }
#endif
            Spacer(minLength: 8)
            RecipeSourceLines(recipe: recipe)
            Spacer(minLength: 8)
            HFlow(itemSpacing: 12, rowSpacing: 8) {
                if let courseName = viewModel.courseName {
                    RecipeChip(systemImage: "fork.knife.circle", accessibilityLabel: "Course: \(courseName)") {
                        Text(courseName)
                    }
                }
                if !recipe.yield.isEmpty {
                    RecipeChip(systemImage: "circle.grid.2x2", accessibilityLabel: "Yield: \(recipe.yield)") {
                        Text(recipe.yield)
                    }
                }
                if let servings = recipe.servings, servings > 0 {
                    RecipeChip(systemImage: "person.2", accessibilityLabel: "Servings: \(servings)") {
                        Text(servings, format: .number)
                    }
                }
            }
        }
        // Same vertical inset as the photo, so the title tops out level with it and the chips
        // bottom out level with it.
        .padding(.horizontal, 16)
        .padding(.vertical, 8)
    }
}

private struct RecipeSourceLines: View {
    let recipe: Recipe

    var body: some View {
        let sourceDetails = recipe.sourceDetails.trimmingCharacters(in: .whitespaces)
        if !recipe.source.isEmpty || !sourceDetails.isEmpty {
            VStack(spacing: 4) {
                if !recipe.source.isEmpty {
                    Label {
                        Text(recipe.source.attributedWithWebLinks)
                    } icon: {
                        Image(systemName: "text.book.closed")
                    }
                    .multilineTextAlignment(.center)
                    .accessibilityLabel("Source: \(recipe.source)")
                }
                if !sourceDetails.isEmpty {
                    if let url = URL(string: sourceDetails),
                       url.scheme?.lowercased().starts(with: "http") == true {
                        Link(destination: url) {
                            Text(sourceDetails)
                                .lineLimit(2)
                                .truncationMode(.middle)
                        }
                        #if os(macOS)
                        .help(sourceDetails)
                        #endif
                    } else {
                        // Still links any URL within the text, e.g. "Adapted from https://…"
                        Text(sourceDetails.attributedWithWebLinks)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
        }
    }
}

private struct RecipeHeaderImage: View {
    @Bindable var viewModel: RecipeDetailViewModel
    let recipe: Recipe
    let size: CGFloat

    var body: some View {
        if recipe.imageFilename != nil {
            Button {
                viewModel.showFullImage()
            } label: {
                RecipeImageView(recipe: recipe, imageFrameSize: size)
                    .shadow(radius: 2)
            }
            .buttonStyle(.plain)
            .padding(8)
            .accessibilityLabel("Recipe photo")
            .accessibilityHint("Shows the full-size image")
        }
    }
}

/// Favorite/Want to Make/preparation times, and rating/difficulty
private struct PrepTimeAndRatingsAndMiscSection: View {
    let recipe: Recipe

    var body: some View {
        VStack(spacing: 12) {
            if recipe.isFavorite || recipe.wantToMake {
                HFlow(itemSpacing: 24, rowSpacing: 12) {
                    if recipe.isFavorite {
                        Label {
                            Text("Favorite")
                        } icon: {
                            Image(systemName: "heart.fill")
                                .foregroundStyle(.red)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Marked as Favorite")
                    }
                    if recipe.wantToMake {
                        Label {
                            Text("Want to Make")
                        } icon: {
                            Image(systemName: "bookmark")
                                .foregroundStyle(Color.green.opacity(0.8))
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Marked as Want to Make")
                    }
                }
            }
            if !recipe.preparationTimes.isEmpty {
                HFlow(itemSpacing: 12, rowSpacing: 8) {
                    ForEach(recipe.preparationTimes) { prepTime in
                        RecipeChip(
                            systemImage: "clock",
                            accessibilityLabel: "Preparation time: type: \(prepTime.type), duration: \(prepTime.timeString)"
                        ) {
                            VStack {
                                Text(prepTime.type)
                                    .font(.caption)
                                Text(prepTime.timeString)
                            }
                        }
                    }
                }
            }
            HFlow(alignment: .top, itemSpacing: 60, rowSpacing: 30) {
                RatingView(recipe: recipe, showLabel: false)
                DifficultyView(recipe: recipe, showLabel: false)
            }
            .padding(.top, 4)
        }
        .padding(8)
        .modifier(RecipeSectionBoxModifier(fillsWidth: false))
    }
}

private struct IntroductionSection: View {
    let recipe: Recipe
    var body: some View {
        if !recipe.introduction.isEmpty {
            Text(recipe.introduction)
                .italic()
                .fixedSize(horizontal: false, vertical: true)
                .padding()
        }
        else {
            VStack {}
                .padding(1)
        }
    }
}

// MARK: - Ingredients and Directions

/// Ingredients beside directions when the column is wide enough for both to read comfortably,
/// stacked otherwise (e.g., iPad portrait with the recipe list showing).
private struct IngredientsAndDirectionsSection: View {
    @Bindable var viewModel: RecipeDetailViewModel
    let recipe: Recipe

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .top, spacing: 8) {
                IngredientsSection(viewModel: viewModel, recipe: recipe)
                    .frame(maxWidth: 360)
                DirectionsSection(viewModel: viewModel, recipe: recipe)
            }
            // See RecipeHeaderSection for why the ideal width is pinned.
            .frame(idealWidth: 640, maxWidth: .infinity)
            VStack(spacing: 8) {
                IngredientsSection(viewModel: viewModel, recipe: recipe)
                DirectionsSection(viewModel: viewModel, recipe: recipe)
            }
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
                        .modifier(SubheadingStyle())
                        .padding(.top, 8)
                        .padding(.bottom, 6)
                } else {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("•")
                            .bold()
                        let parsed = viewModel.scaledIngredientDisplay(ingredient)
                        if parsed.hasQuantity {
                            (Text(parsed.quantity)
                                .fontWeight(.semibold) +
                             Text(parsed.remainder.isEmpty ? "" : " \(parsed.remainder)")
                                .fontWeight(.regular))
                                .fixedSize(horizontal: false, vertical: true)
                                .accessibilityElement(children: .combine)
                        } else {
                            Text(ingredient.text)
                                .fixedSize(horizontal: false, vertical: true)
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
            IngredientsSectionActions(viewModel: viewModel, recipe: recipe)
                .padding(.bottom, 4)
                .padding(.top, 16)
        }
        .modifier(RecipeSectionBoxModifier())
    }
}

/// The ingredients box footer. Side by side when the box has the width for it, stacked when it
/// doesn't.
private struct IngredientsSectionActions: View {
    @Bindable var viewModel: RecipeDetailViewModel
    let recipe: Recipe

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) {
                IngredientsScaleButton(viewModel: viewModel)
                IngredientsAddToListButton(viewModel: viewModel, recipe: recipe)
            }
            VStack(alignment: .leading, spacing: 8) {
                IngredientsScaleButton(viewModel: viewModel)
                IngredientsAddToListButton(viewModel: viewModel, recipe: recipe)
            }
        }
    }
}

private struct IngredientsScaleButton: View {
    @Bindable var viewModel: RecipeDetailViewModel

    var body: some View {
        Button("Scale…", systemImage: "slider.horizontal.3") {
            viewModel.isIngredientScalePopoverShowing = true
        }
        .modifier(IngredientsActionButtonModifier())
        .popover(isPresented: $viewModel.isIngredientScalePopoverShowing) {
            IngredientScalePopoverContent(viewModel: viewModel)
        }
    }
}

private struct IngredientsAddToListButton: View {
    @Bindable var viewModel: RecipeDetailViewModel
    let recipe: Recipe

    var body: some View {
        Button("Add to List…", systemImage: "cart.badge.plus") {
            viewModel.isAddToShoppingListShowing = true
        }
        .modifier(IngredientsActionButtonModifier())
        .sheet(isPresented: $viewModel.isAddToShoppingListShowing) {
            AddToShoppingListView(
                recipe: recipe,
                // Whatever the ingredients list is currently showing is what gets added, so a
                // recipe being read at half scale adds half-scale amounts.
                scaleFactor: viewModel.ingredientScaleFactor,
                scaleLabel: viewModel.isIngredientScaleActive ? viewModel.ingredientScalePercentLabel : nil
            )
        }
    }
}

/// Shared appearance for the small actions under the ingredients list: link-styled text on all
/// platforms, so should look like platform-appropriate controls instead of additional list item
private struct IngredientsActionButtonModifier: ViewModifier {
    func body(content: Content) -> some View {
        content
            #if os(macOS)
            .buttonStyle(.link)
            #else
            .buttonStyle(.borderless)
            #endif
            .controlSize(.small)
    }
}

private struct IngredientScalePopoverContent: View {
    @Bindable var viewModel: RecipeDetailViewModel

    var body: some View {
        VStack(spacing: 12) {
            HStack {
                Button {
                    viewModel.isIngredientScalePopoverShowing = false
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .symbolRenderingMode(.hierarchical)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Close")
                #if os(macOS)
                .help("Close")
                .keyboardShortcut(.escape, modifiers: [])
                #endif

                Spacer(minLength: 0)
            }

            HStack {
                TextField("Scale by:", value: $viewModel.ingredientScalePercent,
                          format: .percent.precision(.fractionLength(2))
                )
                    .frame(width: 80)
            }
            Slider(value: $viewModel.ingredientScalePercent, in: 0.25...2)

            HStack(spacing: 8) {
                IngredientScalePresetButton(
                    title: "Half",
                    accessibilityLabel: "Half recipe",
                    isSelected: viewModel.isIngredientScaleNear(0.5)
                ) {
                    viewModel.ingredientScalePercent = 0.5
                }
                IngredientScalePresetButton(
                    title: "Two-Thirds",
                    accessibilityLabel: "Two-thirds recipe",
                    isSelected: viewModel.isIngredientScaleNear(2.0 / 3.0)
                ) {
                    viewModel.ingredientScalePercent = 2.0 / 3.0
                }
                IngredientScalePresetButton(
                    title: "Double",
                    accessibilityLabel: "Double recipe",
                    isSelected: viewModel.isIngredientScaleNear(2.0)
                ) {
                    viewModel.ingredientScalePercent = 2.0
                }
            }

            Button("Reset") {
                viewModel.resetIngredientScale()
            }
            .frame(maxWidth: .infinity)
            .buttonStyle(.borderless)
            .controlSize(.small)
            .disabled(!viewModel.isIngredientScaleActive)
            Spacer()
            Text("Recipe will temporarily display with scaled measurements, or you can…")
                .font(.caption)
                .accessibilityLabel("Recipe will temporarily display with scaled measurements, or save as new recipe below.")
            Button("Save as New Recipe…") {
                Task { await viewModel.saveAsScaledRecipe() }
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
                let direction = recipe.directions[index]
                if direction.isHeading ?? false {
                    Text(direction.text)
                        .modifier(SubheadingStyle())
                        .padding(.top, 8)
                        .padding(.bottom, 6)
                } else {
                    // Omit headings from step count
                    let stepNumber = recipe.directions.prefix(index).filter { $0.isHeading != true }.count + 1
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text("\(stepNumber).")
                            .bold()
                            .monospacedDigit()
                            .foregroundStyle(.recipeDetailBoxForeground2)
                            // Fixed column so the text starts at the same x for "9." and "10."
                            .frame(minWidth: 24, alignment: .trailing)
                        Text(direction.text)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    .padding(.bottom, 8)
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
        .modifier(RecipeSectionBoxModifier())
    }
}

// MARK: - Notes, Variations, Tags

private struct NotesSection: View {
    let recipe: Recipe
    var body: some View {
        if !recipe.notes.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Notes")
                    .modifier(TitleStyle())
                ForEach(recipe.notes.indices, id: \.self) { index in
                    let note = recipe.notes[index]
                    VStack(alignment: .leading, spacing: 4) {
                        if !note.title.isEmpty {
                            Text(note.title)
                                .modifier(SubheadingStyle())
                        }
                        Text(note.content)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .modifier(RecipeSectionBoxModifier())
        }
    }
}

private struct VariationsSection: View {
    let recipe: Recipe
    var body: some View {
        if !recipe.variations.isEmpty {
            VStack(alignment: .leading, spacing: 10) {
                Text("Variations")
                    .modifier(TitleStyle())
                ForEach(recipe.variations.indices, id: \.self) { index in
                    let variation = recipe.variations[index]
                    VStack(alignment: .leading, spacing: 4) {
                        if !variation.variationName.isEmpty {
                            Text(variation.variationName)
                                .modifier(SubheadingStyle())
                        }
                        Text(variation.text)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .modifier(RecipeSectionBoxModifier())
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
                HFlow(itemSpacing: 8, rowSpacing: 8) {
                    ForEach(viewModel.recipeTags, id: \.id) { tag in
                        RecipeChip(systemImage: "tag", accessibilityLabel: "Tag: \(tag.name)") {
                            Text(tag.name)
                        }
                    }
                }
            }
            .modifier(RecipeSectionBoxModifier())
        }
    }
}

// MARK: - Shared pieces

/// A capsule with a leading symbol, used for most pieces of recipe metadata (prep time, yield, etc.)
private struct RecipeChip<Content: View>: View {
    let systemImage: String
    var iconColor: Color? = nil
    let accessibilityLabel: String
    @ViewBuilder let content: Content

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: systemImage)
                .foregroundStyle(iconColor ?? Color.primary)
            content
        }
        .padding(.vertical, 4)
        .padding(.horizontal, 12)
        .background(Color.recipeDetailPageBackgroundA.opacity(0.66), in: .capsule)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }
}

/// Section titles ("Ingredients", "Notes", etc.)
private struct TitleStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.title2)
            .bold()
            .padding(.top, 8)
            .padding(.bottom, 8)
            .accessibilityAddTraits(.isHeader)
    }
}

/// Headings within a section (ingredient groups, direction phases, note titles)
private struct SubheadingStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .font(.headline)
            .foregroundStyle(.recipeDetailBoxForeground2)
            .fixedSize(horizontal: false, vertical: true)
    }
}

/// The card that most recipe sections live in (can opt in or out of filling entire width; most fill)
private struct RecipeSectionBoxModifier: ViewModifier {
    var fillsWidth = true

    func body(content: Content) -> some View {
        Group {
            if fillsWidth {
                content
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                content
            }
        }
            .padding(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
            .background(Color.recipeDetailBoxBackground)
            .clipShape(.rect(cornerRadius: 12))
            .shadow(color: Color.recipeDetailBoxShadow.opacity(0.7), radius: 3, x:1, y:1)
            .padding(EdgeInsets(top: 4, leading: 4, bottom: 4, trailing: 4))
    }
}



#Preview {
    RecipeDetailView(recipe: SampleData.sampleRecipes[0])
        .environment(ChefViewSessionStore())
}
