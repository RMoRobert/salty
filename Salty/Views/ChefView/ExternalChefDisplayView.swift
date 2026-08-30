//
//  ExternalChefDisplayView.swift
//  Salty
//
//  Contains what the TV (or external display) shows while Screen Mirroring is active:
//  the recipe currently open in Chef View on iPhone/iPad, or placeholder tellign to open one.
//  Root of the external-display scene (see ExternalDisplaySceneDelegate); iOS-only, since macOS
//  can just move the Chef View window there instead.
//
//  Deliberately composed from the same panes as ChefView, driven by a ChefViewModel of its own over
//  the same shared session store. That way, steps and ingredient checks made on the phone appear here
//  live, without any messaging between the scenes. Leaves out interactive chrome from ChefView
//  (header buttons, controls bar, drawer) since this display can't be touched and user can do on
//  iPhone/iPad instead. The display-style and text-size preferences are the same @AppStorage values the
//  phone adjusts, effectively turning that into a remote for this display — as does scrolling the
//  ingredient list, which this display follows (ChefIngredientsScrollSync) since it has no way to
//  scroll a long list itself.
//
//  The one thing sized specifically for here is the type. A TV hands the app a canvas several times
//  a phone's, so text laid out in the same points comes out around half the size it should be; the
//  display's measured width sets `chefFontScale` for everything below (ChefViewTextSize).
//

#if !os(macOS)

import SwiftUI
import SaltyCore

struct ExternalChefDisplayView: View {
    @Environment(ChefViewSessionStore.self) private var sessionStore

    /// How much bigger this display is than the one Chef View's sizes were chosen for. Measured
    /// rather than assumed, since a mirrored TV, an HDMI adapter and a Studio Display all hand the
    /// app different canvases. See ChefViewTextSize.externalDisplayScale(forWidth:).
    @State private var fontScale: CGFloat = 1

    /// Read in `body`, so observation keeps the TV following the phone's Chef View.
    private var coordinator: ChefExternalDisplayCoordinator { .shared }

    var body: some View {
        Group {
            if let launch = coordinator.activeLaunch {
                ExternalChefRecipeView(launch: launch, sessionStore: sessionStore)
                    // A new recipe (or the same one rescaled) rebuilds from scratch: the view model
                    // is keyed to one recipe id and scale for its lifetime.
                    .id(launch)
            } else {
                idleView
            }
        }
        .background(
            LinearGradient(
                colors: [Color.recipeDetailPageBackgroundA, Color.recipeDetailPageBackgroundB],
                startPoint: .top, endPoint: .bottom
            )
            .ignoresSafeArea()
        )
        .foregroundStyle(Color.recipeDetailBoxForeground)
        .fontDesign(.rounded)
        .onGeometryChange(for: CGFloat.self) { proxy in
            proxy.size.width
        } action: { width in
            fontScale = ChefViewTextSize.externalDisplayScale(forWidth: width)
        }
        // Measured here rather than around the recipe alone, so the placeholder below is sized for
        // the room as well. Everything drawn with `chefFont(_:)` follows from this one value; the
        // phone's text-size stepper still applies on top of it.
        .environment(\.chefFontScale, fontScale)
    }

    /// `ContentUnavailableView` draws its own type, so it has no `chefFont(_:)` to follow. Dynamic
    /// Type is the only handle it offers, and one size per rough class of display is plenty for a
    /// screen showing one sentence.
    private var idleView: some View {
        ContentUnavailableView {
            Label("Chef View", systemImage: "frying.pan")
        } description: {
            Text("Open a recipe from Salty in Chef View on your iPhone or iPad, and it will appear here.")
        }
        .dynamicTypeSize(ChefViewTextSize.externalDisplayTypeSize(forScale: fontScale))
    }
}

/// One recipe, laid out for a typical TV: name across the top, ingredients on the left, directions
/// filling the rest. Kept private to external display. Every subview it composes is shared
/// with ChefView, so any changes there carry over to here, too.
private struct ExternalChefRecipeView: View {
    @State private var viewModel: ChefViewModel

    @AppStorage(ChefViewDisplayStyle.storageKey) private var displayStyle: ChefViewDisplayStyle = .continuous
    @AppStorage(ChefViewTextSize.storageKey) private var textSizeLevel = ChefViewTextSize.defaultLevel

    init(launch: ChefViewLaunch, sessionStore: ChefViewSessionStore) {
        _viewModel = State(
            initialValue: ChefViewModel(
                recipeId: launch.recipeId,
                scaleFactor: launch.scalePercent,
                sessionStore: sessionStore
            )
        )
    }

    private var textSize: DynamicTypeSize {
        ChefViewTextSize.size(for: textSizeLevel)
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
        }
        // Inset whole layout to account for overscan, etc., since TV doesn't specify "safe areas":
        .padding(.horizontal, 40)
        .padding(.vertical, 24)
        // The scale itself is measured once at the root (ExternalChefDisplayView), so the idle
        // placeholder gets it too; everything below just draws with `chefFont(_:)`.
        .task { await viewModel.loadRecipeIfNeeded() }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(viewModel.recipeName)
                .chefFont(.largeTitle)
                .bold()
                .lineLimit(1)
            if viewModel.scaleFactor != 1.0 {
                Text(viewModel.scaleFactor, format: .percent)
                    .chefFont(.title2)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Scaled to \(viewModel.scaleFactor.formatted(.percent))")
            }
            Spacer()
        }
        .padding(.bottom, 12)
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
                description: Text("No directions in this recipe.")
            )
        } else {
            HStack(spacing: 0) {
                ExternalChefIngredientsPane(viewModel: viewModel)
                    .containerRelativeFrame(.horizontal) { length, _ in
                        // Wider than ChefView's regular-width layout, in both share and cap. The
                        // text on this display is around twice the size, so a pane sized in points
                        // like the phone's holds half as much of an ingredient per line — and the
                        // directions still have plenty left over at these widths.
                        min(max(length * 0.4, 260), 820)
                    }
                    .dynamicTypeSize(textSize)
                Divider()
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
            }
        }
    }
}

#endif
