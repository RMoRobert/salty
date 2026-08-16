//
//  ExternalChefIngredientsPane.swift
//  Salty
//
//  The ingredients pane as the external display shows it: everything at once if it can possibly
//  manage it, and only then a scrolling list that follows the phone.
//
//  Following the phone (ChefIngredientsScrollSync) covers a long list, but it can't cover a list
//  that the *phone* shows in full: a phone with nothing to scroll has nothing to report, so if the
//  TV can't fit that same list, its last rows would be unreachable from either device. An iPad's
//  Chef View pane is full-height where this one has a header above it, and the type here is around
//  twice the size, so "fits on the phone, doesn't fit on the TV" is an ordinary case rather than an
//  exotic one.
//
//  So the display gives up some size before it gives up rows: it tries the full external text size,
//  then a few steps down, and takes the first that shows the whole list. Even the smallest step is
//  well above the size this display used before it scaled text at all, and lists too long for any
//  of them fall through to scrolling, where the phone is back in charge.
//

#if !os(macOS)

import SwiftUI

struct ExternalChefIngredientsPane: View {
    @Bindable var viewModel: ChefViewModel

    @Environment(\.chefFontScale) private var fontScale

    var body: some View {
        // Candidates are plain, unstretched lists so their ideal heights are what `ViewThatFits`
        // compares; the top alignment is applied to whichever one it settles on.
        ViewThatFits(in: .vertical) {
            fittedList(1)
            fittedList(0.86)
            fittedList(0.74)
            fittedList(0.64)
            // The floor, and where the guarantee comes from: at this step the pane holds more rows
            // than any iPhone or iPad Chef View can show without scrolling, so a list the phone
            // can't scroll is one this display can still show whole. It is also still larger than
            // the text this display drew at before it scaled anything.
            fittedList(0.55)
            // Longer than that, so the phone has scrolling to do — and this list follows it.
            ChefViewIngredientsPane(viewModel: viewModel, scrollSync: .follows)
        }
        .frame(maxHeight: .infinity, alignment: .top)
    }

    /// The whole list at a fraction of the display's text scale.
    private func fittedList(_ scale: CGFloat) -> some View {
        ChefViewIngredientsList(viewModel: viewModel)
            .environment(\.chefFontScale, fontScale * scale)
    }
}

#endif
