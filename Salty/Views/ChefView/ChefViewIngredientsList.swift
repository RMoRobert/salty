//
//  ChefViewIngredientsList.swift
//  Salty
//
//  The ingredient rows themselves, with no scroll view around them. Chef View wraps this in one
//  (ChefViewIngredientsPane); the external display measures it first and only scrolls if it must
//  (ExternalChefIngredientsPane), which is why the rows and the scrolling live apart.
//

import SwiftUI
import SaltyCore

struct ChefViewIngredientsList: View {
    @Bindable var viewModel: ChefViewModel
    /// False in the compact-width drawer, where the sheet's navigation title already says it.
    var showsTitle = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if showsTitle {
                Text("Ingredients")
                    .chefFont(.title2)
                    .bold()
                    .padding(.bottom, 4)
            }

            // Identified by index, which is both what checked state is keyed by and what a
            // following external display is sent to scroll to.
            ForEach(viewModel.ingredients.indices, id: \.self) { index in
                let ingredient = viewModel.ingredients[index]
                if ingredient.isHeading {
                    Text(ingredient.text)
                        .chefFont(.title3)
                        .bold()
                        .foregroundStyle(.recipeDetailBoxForeground2)
                        .padding(.top, 12)
                        .id(index)
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
                    .id(index)
                }
            }

            if viewModel.isScaleActive {
                Text("Scaled to \(viewModel.scalePercentLabel)%")
                    .chefFont(.footnote)
                    .foregroundStyle(.secondary)
                    .padding(.top, 12)
            }
        }
        // Marks the rows as this list's scroll targets when there is a scroll view above it, and
        // does nothing at all when there isn't. Kept here so it stays attached to the VStack itself.
        .scrollTargetLayout()
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding()
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
        // Checked rows keep full contrast: the filled checkmark says they're done, and dimming them
        // works against a list that has to stay readable from across the kitchen (or the room).
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
