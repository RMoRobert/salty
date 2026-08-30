//
//  ChefViewControlsBar.swift
//  Salty
//
//  The bottom bar shared by both display modes: step back, where you are, step forward.
//
//  "Next" completes the current step on its way past, so working through a recipe with this bar
//  alone leaves the check-offs correct without any extra tapping. It stays in place all the way
//  through and simply disables once the last step is done — the buttons shouldn't move or swap out
//  underneath hands that have learned where they are.
//
//  Marking a recipe prepared lives in the header's More menu, not here. It's a once-per-cook action
//  and it was the widest thing in the bar — squeezing the chevrons until "Previous" truncated on an
//  iPad in portrait. Three items (back, where you are, forward) is what this bar is for.
//

import SwiftUI
import SaltyCore

struct ChefViewControlsBar: View {
    @Bindable var viewModel: ChefViewModel

    #if !os(macOS)
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    #endif

    /// An iPhone bar can't carry two titled buttons alongside the progress. The chevrons drop their
    /// titles there — still the biggest targets in the bar, and still labelled for VoiceOver.
    private var isCompact: Bool {
        #if os(macOS)
        false
        #else
        horizontalSizeClass == .compact
        #endif
    }

    var body: some View {
        HStack(spacing: 16) {
            Button("Previous", systemImage: "chevron.left") {
                withAnimation(.smooth) { viewModel.goToPreviousStep() }
            }
            .buttonStyle(.bordered)
            .controlSize(.large)
            .disabled(!viewModel.canGoToPreviousStep)
            .modifier(ChefBarLabelStyle(iconOnly: isCompact))

            Spacer(minLength: 0)

            progress

            Spacer(minLength: 0)

            Button("Next", systemImage: "chevron.right") {
                withAnimation(.smooth) { viewModel.goToNextStep() }
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .disabled(!viewModel.canAdvance)
            .modifier(ChefBarLabelStyle(iconOnly: isCompact))
        }
        // Everything in this bar is fixed-size chrome; only the spacers give. Without this a tight
        // bar compresses the buttons until their titles wrap one letter per line.
        .fixedSize(horizontal: false, vertical: true)
        .lineLimit(1)
        .padding(.horizontal)
        .padding(.vertical, 10)
        // Matches the header: the controls stay a usable size however large the recipe text is set.
        .dynamicTypeSize(...DynamicTypeSize.xxLarge)
    }

    @ViewBuilder
    private var progress: some View {
        VStack(spacing: 2) {
            if let label = viewModel.currentStepProgressLabel {
                Text(label)
                    .font(.headline)
                    .monospacedDigit()
            }
        }
        .lineLimit(1)
        .fixedSize()
    }

}

// MARK: - Label style

/// Titles alongside the chevrons where the bar is wide enough, icons alone where it isn't.
/// A modifier rather than a ternary because `LabelStyle` values have no common concrete type.
private struct ChefBarLabelStyle: ViewModifier {
    let iconOnly: Bool

    func body(content: Content) -> some View {
        if iconOnly {
            content.labelStyle(.iconOnly)
        } else {
            content.labelStyle(.titleAndIcon)
        }
    }
}
