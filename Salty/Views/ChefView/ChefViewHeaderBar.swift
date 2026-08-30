//
//  ChefViewHeaderBar.swift
//  Salty
//
//  Chef View's top chrome: leave, recipe name, and the two controls that change how the recipe is
//  presented (text size and display mode). Deliberately outside the Dynamic Type override the
//  content carries — the controls should stay a normal, predictable size no matter how large the
//  recipe text is dialled up.
//

import SwiftUI
import SaltyCore

struct ChefViewHeaderBar: View {
    @Bindable var viewModel: ChefViewModel
    @Binding var displayStyle: ChefViewDisplayStyle
    @Binding var textSizeLevel: Int
    /// True at compact width, where the ingredients live behind a drawer rather than a pane.
    let showsIngredientsButton: Bool
    let onDone: () -> Void

    @State private var isTextSizePopoverShowing = false

    var body: some View {
        HStack(spacing: 12) {
            #if !os(macOS)
            Button("Done", action: onDone)
                .buttonStyle(.bordered)
                .lineLimit(1)
                .fixedSize()
            #endif

            if showsIngredientsButton {
                Button {
                    viewModel.isIngredientsDrawerShowing = true
                } label: {
                    Label("Ingredients", systemImage: "list.bullet.clipboard")
                        .chefHeaderIcon()
                }
                .buttonStyle(.bordered)
            }

            Spacer(minLength: 8)

            Text(viewModel.recipeName)
                .font(.headline)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 8)

            textSizeControl

            Button {
                withAnimation(.smooth) {
                    displayStyle = displayStyle.toggled
                }
            } label: {
                Label(displayStyle.toggled.displayName, systemImage: displayStyle.toggled.symbolName)
                    .chefHeaderIcon()
            }
            .buttonStyle(.bordered)
            #if os(macOS)
            .help("Show \(displayStyle.toggled.displayName)")
            #endif

            moreMenu
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        // The recipe name is the only thing here that should give when the bar is tight; the
        // controls keep their intrinsic width rather than compressing until their titles wrap.
        .fixedSize(horizontal: false, vertical: true)
        // The content below can be dialled up to accessibility sizes; the chrome shouldn't follow
        // it there, or the bar alone would fill the screen.
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }

    /// One compact button in the bar; the slider itself lives in the popover, where it has room to
    /// be dragged. See ChefViewTextSizePopover.
    private var textSizeControl: some View {
        Button {
            isTextSizePopoverShowing = true
        } label: {
            Label("Text Size", systemImage: "textformat.size")
                .chefHeaderIcon()
        }
        .buttonStyle(.bordered)
        .accessibilityValue(ChefViewTextSize.accessibilityValue(for: textSizeLevel))
        #if os(macOS)
        .help("Text Size")
        #endif
        .popover(isPresented: $isTextSizePopoverShowing) {
            ChefViewTextSizePopover(textSizeLevel: $textSizeLevel)
                // Stay a popover on iPhone rather than adapting into a sheet -- it's a small
                // adjustment made while looking at the text it changes.
                .presentationCompactAdaptation(.popover)
        }
    }

    private var moreMenu: some View {
        Menu {
            Picker("Display", selection: $displayStyle) {
                ForEach(ChefViewDisplayStyle.allCases) { style in
                    Label(style.displayName, systemImage: style.symbolName).tag(style)
                }
            }
            .pickerStyle(.inline)

            Divider()

            // Now the only place this action lives, so it also has to carry the feedback the
            // controls bar used to show: once the date is stamped it settles into a filled, disabled
            // "Prepared Today" rather than a greyed-out invitation to do something already done.
            Button(
                viewModel.didMarkAsMade ? "Prepared Today" : "Mark as Prepared",
                systemImage: viewModel.didMarkAsMade ? "checkmark.circle.fill" : "checkmark.circle"
            ) {
                viewModel.requestMarkAsMade()
            }
            .disabled(viewModel.isMarkingAsMade || viewModel.didMarkAsMade)

            Button("Start Over", systemImage: "arrow.counterclockwise") {
                withAnimation {
                    viewModel.startOver()
                }
            }
            .disabled(!viewModel.hasProgress)
        } label: {
            Label("More", systemImage: isLiquidGlassAvailable() ? "ellipsis" : "ellipsis.circle")
                .chefHeaderIcon()
        }
        .menuIndicator(.hidden)
        // Bordered like every other control in this bar. As a bare glyph it was the smallest target
        // here *and* the one nearest the screen edge, which is the worst combination — the border
        // gives it the same padded hit area its neighbours already had.
        .buttonStyle(.bordered)
        // Avoid stretching to fill on macOS 15 (OK on 26 without this):
        .fixedSize()
    }
}

// MARK: - Icon sizing

private extension View {
    /// Renders a header-bar button's label icon-only inside a fixed square.
    ///
    /// A bordered button sizes to its label, and these glyphs are nowhere near the same shape —
    /// `ellipsis` is a flat row of dots, the display-style symbol is a tall rectangle — so left to
    /// themselves the capsules came out visibly different heights next to each other. The square
    /// is what makes them one matching set, and it gives every icon the same hit target regardless
    /// of how small its glyph happens to be.
    func chefHeaderIcon() -> some View {
        labelStyle(.iconOnly)
            .frame(width: 26, height: 26)
    }
}
