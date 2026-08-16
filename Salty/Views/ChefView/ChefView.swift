//
//  ChefView.swift
//  Salty
//
//  Full-screen, large-print view for actually cooking from a recipe — legible from across the
//  kitchen, and (mirrored via AirPlay) from a TV.
//
//  Pure presentation: no new tables, no migrations, no sync. Cooking progress lives in the
//  app-level ChefViewSessionStore for the length of the app session; everything else here is a
//  display preference in @AppStorage.
//
//  Presented as a full-screen cover on iOS and as its own window on macOS (see SaltyApp's
//  "chef-view-window" scene), so the Chef View window can go full screen on a TV while the main
//  app stays usable.
//

import SwiftUI
import SaltyCore

struct ChefView: View {
    @State private var viewModel: ChefViewModel
    @Environment(\.dismiss) private var dismiss

    @AppStorage(ChefViewDisplayStyle.storageKey) private var displayStyle: ChefViewDisplayStyle = .continuous
    @AppStorage(ChefViewTextSize.storageKey) private var textSizeLevel = ChefViewTextSize.defaultLevel

    #if !os(macOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    /// The session store is handed in rather than read from the environment here, so the view model
    /// can be built in `init` (the environment isn't available yet at that point).
    init(recipe: Recipe, scaleFactor: Double = 1.0, sessionStore: ChefViewSessionStore) {
        _viewModel = State(
            initialValue: ChefViewModel(recipe: recipe, scaleFactor: scaleFactor, sessionStore: sessionStore)
        )
    }

    /// For the macOS window, whose Codable window value carries only a recipe id.
    init(recipeId: String, scaleFactor: Double = 1.0, sessionStore: ChefViewSessionStore) {
        _viewModel = State(
            initialValue: ChefViewModel(recipeId: recipeId, scaleFactor: scaleFactor, sessionStore: sessionStore)
        )
    }

    /// At compact width the directions take the whole screen and the ingredients move to a drawer:
    /// ingredients matter early, directions dominate mid-cook.
    private var isCompact: Bool {
        #if os(macOS)
        false
        #else
        horizontalSizeClass == .compact
        #endif
    }

    private var textSize: DynamicTypeSize {
        ChefViewTextSize.size(for: textSizeLevel)
    }

    var body: some View {
        VStack(spacing: 0) {
            ChefViewHeaderBar(
                viewModel: viewModel,
                displayStyle: $displayStyle,
                textSizeLevel: $textSizeLevel,
                showsIngredientsButton: isCompact && viewModel.recipe != nil,
                onDone: { dismiss() }
            )
            Divider()
            content
        }
        .background(
            LinearGradient(
                colors: [Color.recipeDetailPageBackgroundA, Color.recipeDetailPageBackgroundB],
                startPoint: .top, endPoint: .bottom
            )
            // Only the *background* crosses into the safe area; the bars above stay inside it, so
            // nothing lands under a notch or Dynamic Island. Without this the gradient stops at the
            // safe-area edge and leaves a plain strip along the top.
            .ignoresSafeArea()
        )
        .foregroundStyle(Color.recipeDetailBoxForeground)
        .fontDesign(.rounded)
        #if !os(macOS)
        // Cooking is the one screen that earns true full screen: the clock and Wi-Fi glyphs are
        // noise on a recipe being read from across the kitchen or mirrored to a TV, and the home
        // indicator sits directly under the controls bar. Both are requests — the system still
        // shows them when it needs to (during a call, for instance). "Done" stays in the header as
        // the way out, so hiding the system chrome never leaves the view without a visible exit.
        .statusBarHidden(true)
        .persistentSystemOverlays(.hidden)
        #endif
        .navigationTitle(viewModel.recipeName)
        .task { await viewModel.loadRecipeIfNeeded() }
        // Paired explicitly rather than relying on task cancellation: the display must come back
        // under the system's control the moment Chef View goes away, on every exit path.
        .onAppear { ScreenSleepBlocker.shared.begin() }
        .onDisappear { ScreenSleepBlocker.shared.end() }
        .sheet(isPresented: $viewModel.isIngredientsDrawerShowing) {
            ingredientsDrawer
        }
        // One dialog for both offers of the action (the controls bar link and the More menu). Its
        // message is what lets the buttons drop the word "Today" — the date is spelled out here.
        //
        // An alert rather than a confirmationDialog: on iPad a confirmation dialog is presented as a
        // popover, and a popover DROPS the `.cancel`-role button on the assumption that tapping
        // outside will do — so "Do Not Change" simply wouldn't appear there. An alert shows both
        // buttons on every platform and idiom, which is the point of spelling out the safe choice.
        .alert(
            "Mark as Prepared?",
            isPresented: $viewModel.isConfirmingMarkAsMade
        ) {
            Button("Mark as Prepared") {
                Task { await viewModel.markAsMade() }
            }
            // Named for what it does to the data rather than "Cancel": the dialog's whole job is to
            // make clear that confirming overwrites an existing date, so the way out should say the
            // date is left alone. Keeps `.cancel` role, so Esc still picks it.
            Button("Do Not Change", role: .cancel) { }
        } message: {
            Text("Set recipe's  \"Last Prepared\" date to today?")
        }
        // Lives here rather than on the controls bar, which isn't rendered at all for a recipe with
        // no directions — the More menu still offers the action there, so its failure needs to be
        // reportable from the same place the action is.
        .alert(
            "Could Not Save",
            isPresented: Binding(
                get: { viewModel.markAsMadeErrorMessage != nil },
                set: { if !$0 { viewModel.markAsMadeErrorMessage = nil } }
            )
        ) {
            Button("OK", role: .cancel) { viewModel.markAsMadeErrorMessage = nil }
        } message: {
            Text(viewModel.markAsMadeErrorMessage ?? "")
        }
    }

    @ViewBuilder
    private var content: some View {
        if viewModel.recipe == nil {
            ProgressView("Loading recipe…")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if viewModel.steps.isEmpty {
            ContentUnavailableView(
                "No Directions",
                systemImage: "list.number",
                description: Text("This recipe doesn't have any directions to cook from.")
            )
        } else {
            HStack(spacing: 0) {
                if !isCompact {
                    ChefViewIngredientsPane(viewModel: viewModel)
                        .containerRelativeFrame(.horizontal) { length, _ in
                            min(max(length / 3, 260), 460)
                        }
                        .dynamicTypeSize(textSize)
                    Divider()
                }
                VStack(spacing: 0) {
                    Group {
                        switch displayStyle {
                        case .continuous:
                            ChefViewDirectionsList(viewModel: viewModel)
                        case .focus:
                            ChefViewFocusStepView(viewModel: viewModel)
                        }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .dynamicTypeSize(textSize)
                    Divider()
                    ChefViewControlsBar(viewModel: viewModel)
                }
            }
        }
    }

    private var ingredientsDrawer: some View {
        NavigationStack {
            ChefViewIngredientsPane(viewModel: viewModel, showsTitle: false)
                .dynamicTypeSize(textSize)
                .background(Color.recipeDetailPageBackgroundA)
                .foregroundStyle(Color.recipeDetailBoxForeground)
                .fontDesign(.rounded)
                .navigationTitle("Ingredients")
                .toolbarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { viewModel.isIngredientsDrawerShowing = false }
                    }
                }
        }
        .presentationDetents([.medium, .large])
    }
}

#Preview {
    ChefView(recipe: SampleData.sampleRecipes[0], sessionStore: ChefViewSessionStore())
}
