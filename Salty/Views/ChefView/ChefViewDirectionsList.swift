//
//  ChefViewDirectionsList.swift
//  Salty
//
//  Chef View's default presentation: every step visible at once, with the current one highlighted
//  and pulled to the middle of the screen. A strict one-step-at-a-time view answers "what's next?"
//  but not "what did step 4 say?"; this keeps both, and keeps most of the focus benefit.
//

import SwiftUI
import SaltyCore

struct ChefViewDirectionsList: View {
    @Bindable var viewModel: ChefViewModel
    @State private var scrollPosition = ScrollPosition()

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 8) {
                ForEach(viewModel.steps) { step in
                    if step.isHeading {
                        Text(step.text)
                            .chefFont(.title2)
                            .bold()
                            .foregroundStyle(.recipeDetailBoxForeground2)
                            .padding(.top, 20)
                            .padding(.bottom, 4)
                            .id(step.id)
                    } else {
                        ChefViewStepRow(
                            step: step,
                            isCurrent: viewModel.isCurrent(step),
                            isCompleted: viewModel.isCompleted(step),
                            onSelect: { withAnimation(.smooth) { viewModel.select(step) } },
                            onToggleCompleted: { withAnimation(.snappy) { viewModel.toggleCompleted(step) } }
                        )
                        .id(step.id)
                    }
                }

                if viewModel.isScaleActive {
                    Text(viewModel.scaleFootnote)
                        .chefFont(.footnote)
                        .italic()
                        .foregroundStyle(.recipeDetailBoxForeground2)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.top, 20)
                }

                // Lets the last step still settle in the middle of the screen when it's made current.
                Spacer(minLength: 240)
            }
            .scrollTargetLayout()
            .padding()
        }
        .scrollPosition($scrollPosition)
        .onChange(of: viewModel.currentStep?.id) { _, stepId in
            guard let stepId else { return }
            withAnimation(.smooth) {
                scrollPosition.scrollTo(id: stepId, anchor: .center)
            }
        }
    }
}

// MARK: - Row

private struct ChefViewStepRow: View {
    let step: ChefStep
    let isCurrent: Bool
    let isCompleted: Bool
    let onSelect: () -> Void
    let onToggleCompleted: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 14) {
            Button(isCompleted ? "Completed" : "Not Completed",
                   systemImage: isCompleted ? "checkmark.circle.fill" : "circle",
                   action: onToggleCompleted)
                .labelStyle(.iconOnly)
                .buttonStyle(.plain)
                .imageScale(.large)
                .foregroundStyle(isCompleted ? Color.accentColor : Color.secondary)

            Button(action: onSelect) {
                HStack(alignment: .firstTextBaseline, spacing: 10) {
                    if let number = step.number {
                        Text("\(number).")
                            .bold()
                            .monospacedDigit()
                    }
                    Text(step.text)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .contentShape(.rect)
            }
            .buttonStyle(.plain)
            .accessibilityLabel(accessibilityLabel)
            .accessibilityAddTraits(isCurrent ? [.isButton, .isSelected] : .isButton)
        }
        // The current step is a size up and sits on its own card; every other step — done or still
        // to come — reads at full contrast, since a dimmed step is exactly the one being squinted
        // at from across the kitchen. Completion is said with the checkmark instead.
        .chefFont(isCurrent ? .title2 : .title3)
        .padding(.vertical, 10)
        .padding(.horizontal, 12)
        .background {
            if isCurrent {
                RoundedRectangle(cornerRadius: 12)
                    .fill(Color.recipeDetailBoxBackground)
                    .shadow(color: Color.recipeDetailBoxShadow.opacity(0.7), radius: 3, x: 1, y: 1)
            }
        }
    }

    private var accessibilityLabel: String {
        guard let number = step.number else { return step.text }
        return "Step \(number). \(step.text)"
    }
}
