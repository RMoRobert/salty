//
//  ChefViewIngredientsPane.swift
//  Salty
//
//  The ingredients half of Chef View: a large-print, checkable list. Pinned to the left at regular
//  width; presented as a drawer at compact width, where directions need the whole screen.
//

import SwiftUI
import SaltyCore

struct ChefViewIngredientsPane: View {
    @Bindable var viewModel: ChefViewModel
    /// False in the compact-width drawer, where the sheet's navigation title already says it.
    var showsTitle = true

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 10) {
                if showsTitle {
                    Text("Ingredients")
                        .chefFont(.title2)
                        .bold()
                        .padding(.bottom, 4)
                }

                ForEach(viewModel.ingredients.indices, id: \.self) { index in
                    let ingredient = viewModel.ingredients[index]
                    if ingredient.isHeading {
                        Text(ingredient.text)
                            .chefFont(.title3)
                            .bold()
                            .foregroundStyle(.recipeDetailBoxForeground2)
                            .padding(.top, 12)
                    } else {
                        ChefViewIngredientRow(
                            ingredient: ingredient,
                            isChecked: viewModel.isIngredientChecked(at: index),
                            parts: viewModel.scaledIngredientDisplay(ingredient)
                        ) {
                            withAnimation(.snappy) {
                                viewModel.toggleIngredientChecked(at: index)
                            }
                        }
                    }
                }

                if viewModel.isScaleActive {
                    Text("Scaled to \(viewModel.scalePercentLabel)%")
                        .chefFont(.footnote)
                        .foregroundStyle(.secondary)
                        .padding(.top, 12)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding()
        }
    }
}

// MARK: - Row

private struct ChefViewIngredientRow: View {
    let ingredient: Ingredient
    let isChecked: Bool
    let parts: IngredientScaler.DisplayParts
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Image(systemName: isChecked ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isChecked ? Color.accentColor : Color.secondary)
                    .imageScale(.large)
                    .accessibilityHidden(true)
                text
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            // Large tap target: the whole row, not just the text it happens to contain.
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .chefFont(.title3)
        .opacity(isChecked ? 0.45 : 1)
        .padding(.vertical, 2)
        .accessibilityLabel(ingredient.text)
        .accessibilityValue(isChecked ? "Checked" : "Not checked")
        .accessibilityAddTraits(.isButton)
    }

    /// Quantity in semibold and the rest regular, matching how the recipe detail view reads.
    @ViewBuilder
    private var text: some View {
        if parts.hasQuantity {
            Text(parts.quantity).bold()
                + Text(parts.remainder.isEmpty ? "" : " \(parts.remainder)")
        } else {
            Text(ingredient.text)
        }
    }
}
