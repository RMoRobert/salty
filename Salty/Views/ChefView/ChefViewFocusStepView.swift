//
//  ChefViewFocusStepView.swift
//  Salty
//
//  One giant step at a time. Built for the two situations the continuous list handles worst:
//  mirrored to a TV across the room, and hands too messy to aim at anything small. The outer
//  thirds of the screen are the previous/next controls, and a horizontal swipe does the same.
//

import SwiftUI
import SaltyCore

struct ChefViewFocusStepView: View {
    @Bindable var viewModel: ChefViewModel

    /// Enough travel that scrolling a long step's text doesn't read as "next".
    private let swipeThreshold: CGFloat = 60

    var body: some View {
        ZStack {
            stepContent
            tapZones
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        // Simultaneous, not exclusive: a long step still scrolls vertically in the middle column,
        // and the axis check below throws away anything that was really a scroll.
        .simultaneousGesture(
            DragGesture(minimumDistance: swipeThreshold)
                .onEnded { value in
                    guard abs(value.translation.width) > abs(value.translation.height) else { return }
                    withAnimation(.smooth) {
                        if value.translation.width < 0 {
                            viewModel.goToNextStep()
                        } else {
                            viewModel.goToPreviousStep()
                        }
                    }
                }
        )
    }

    @ViewBuilder
    private var stepContent: some View {
        if let step = viewModel.currentStep {
            ScrollView {
                VStack(alignment: .leading, spacing: 20) {
                    if let heading = viewModel.currentSectionHeading {
                        Text(heading)
                            .chefFont(.title3)
                            .bold()
                            .foregroundStyle(.recipeDetailBoxForeground2)
                    }
                    if let number = step.number {
                        Text("\(number).")
                            .chefFont(.title)
                            .bold()
                            .monospacedDigit()
                            .foregroundStyle(.secondary)
                    }
                    Text(step.text)
                        .chefFont(.largeTitle)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 32)
                .padding(.vertical, 28)
                .frame(maxWidth: 900, alignment: .leading)
                .frame(maxWidth: .infinity)
            }
            .id(step.id)
        } else {
            ContentUnavailableView(
                "No Steps",
                systemImage: "list.number",
                description: Text("This recipe doesn't have any directions to cook from.")
            )
        }
    }

    /// Sits above the text: a tap anywhere in the outer third moves a step, with no small target to
    /// aim at. The middle third stays clear so a long step can still be scrolled.
    private var tapZones: some View {
        HStack(spacing: 0) {
            Button {
                withAnimation(.smooth) { viewModel.goToPreviousStep() }
            } label: {
                Color.clear.contentShape(.rect)
            }
            .buttonStyle(.plain)
            .disabled(!viewModel.canGoToPreviousStep)
            .accessibilityLabel("Previous Step")
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)

            Button {
                withAnimation(.smooth) { viewModel.goToNextStep() }
            } label: {
                Color.clear.contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Next Step")
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
