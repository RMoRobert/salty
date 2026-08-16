//
//  ChefViewIngredientsPane.swift
//  Salty
//
//  The ingredients half of Chef View: a large-print, checkable list. Pinned to the left at regular
//  width; presented as a drawer at compact width, where directions need the whole screen.
//
//  The rows live in ChefViewIngredientsList; this is the scrolling around them, and the link that
//  lets an external display's copy follow this one (ChefIngredientsScrollSync).
//

import SwiftUI
import SaltyCore

struct ChefViewIngredientsPane: View {
    @Bindable var viewModel: ChefViewModel
    /// False in the compact-width drawer, where the sheet's navigation title already says it.
    var showsTitle = true
    /// Which end of the phone → external-display scroll link this list is, if either.
    var scrollSync: ChefIngredientsScrollSync = .off

    @State private var scrollPosition = ScrollPosition()

    var body: some View {
        ScrollView {
            ChefViewIngredientsList(viewModel: viewModel, showsTitle: showsTitle)
        }
        .scrollPosition($scrollPosition)
        .chefIngredientsScrollSync(
            scrollSync,
            position: $scrollPosition,
            itemCount: viewModel.ingredients.count
        )
    }
}
