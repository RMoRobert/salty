//
//  ChefIngredientsScrollSync.swift
//  Salty
//
//  Mirrors the ingredient list's scroll position from Chef View on the phone to the external
//  display.
//
//  The external display can't be scrolled — nothing on a TV receives touches — so a list longer
//  than the screen simply stops, with the rest of it unreachable. Rather than shrink the list to
//  fit (which would undo the whole point of the display) the phone reports where it is looking, and
//  the TV goes to the same place: the phone becomes the remote for a list read from across the room.
//
//  The middle of the list is reported as a row, which the TV puts at the top — it reads as "the TV
//  shows what my phone shows, starting here", and it can't scroll the TV past ingredients the phone
//  is still displaying. The two ends are reported as ends rather than as rows, because the TV can
//  hold fewer rows than the phone and "put row N at the top" would then strand everything after it.
//  See ChefIngredientsAnchor.
//
//  A phone list too short to scroll reports `.top` and nothing else: it has no way to say where to
//  look, so the display has to fit the whole list by itself (ExternalChefIngredientsPane).
//
//  Inert on macOS, where Chef View is an ordinary window that can be scrolled wherever it sits.
//

import SwiftUI

/// A Chef View ingredient list's part in phone → external-display mirroring.
enum ChefIngredientsScrollSync {
    /// Neither end of the link: an ingredient list no external display is following.
    case off
    /// The phone's list, reporting where it is looking.
    case publishes
    /// The external display's list, going wherever the phone reports.
    case follows
}

extension View {
    /// Applies to the ingredient list's `ScrollView`. `itemCount` is only a trigger: a following
    /// display can connect before its recipe has loaded, and there is nothing to scroll to until
    /// the rows exist.
    func chefIngredientsScrollSync(
        _ role: ChefIngredientsScrollSync,
        position: Binding<ScrollPosition>,
        itemCount: Int
    ) -> some View {
        modifier(ChefIngredientsScrollSyncModifier(role: role, position: position, itemCount: itemCount))
    }
}

private struct ChefIngredientsScrollSyncModifier: ViewModifier {
    let role: ChefIngredientsScrollSync
    @Binding var position: ScrollPosition
    let itemCount: Int

    /// Top-most row the phone is showing, and whether it has run out of list. Both are needed to
    /// describe one anchor, and they arrive from two different scroll callbacks.
    @State private var topVisibleIndex: Int?
    @State private var isAtEnd = false

    @ViewBuilder
    func body(content: Content) -> some View {
        #if os(macOS)
        content
        #else
        switch role {
        case .off:
            content
        case .publishes:
            // Ingredient rows are identified by their index into the recipe's ingredients, which is
            // also how checked state is keyed — so the id travelling to the TV needs no translation.
            content
                .onScrollTargetVisibilityChange(idType: Int.self) { visible in
                    topVisibleIndex = visible.first
                    publish()
                }
                .onScrollGeometryChange(for: Bool.self) { geometry in
                    // A list that fits its own viewport is never "at the end" — it simply has no
                    // scrolling to report, and saying otherwise would pin the TV to the bottom of a
                    // list the phone is showing all of.
                    let isScrollable = geometry.contentSize.height > geometry.containerSize.height + 1
                    return isScrollable && geometry.visibleRect.maxY >= geometry.contentSize.height - 2
                } action: { _, isAtEnd in
                    self.isAtEnd = isAtEnd
                    publish()
                }
        case .follows:
            content
                .onChange(of: ChefExternalDisplayCoordinator.shared.ingredientAnchor) { _, anchor in
                    scroll(to: anchor)
                }
                .onChange(of: itemCount, initial: true) { _, _ in
                    scroll(to: ChefExternalDisplayCoordinator.shared.ingredientAnchor)
                }
        }
        #endif
    }

    #if !os(macOS)

    private func publish() {
        let anchor: ChefIngredientsAnchor =
            if isAtEnd {
                .bottom
            } else if let topVisibleIndex {
                .item(index: topVisibleIndex)
            } else {
                .top
            }
        ChefExternalDisplayCoordinator.shared.setIngredientAnchor(anchor)
    }

    /// Deliberately unanimated: the phone publishes one of these for every row it scrolls past, and
    /// animating each would leave the TV running behind the list it is meant to be showing.
    private func scroll(to anchor: ChefIngredientsAnchor) {
        switch anchor {
        case .top:
            position.scrollTo(edge: .top)
        case .item(let index):
            position.scrollTo(id: index, anchor: .top)
        case .bottom:
            position.scrollTo(edge: .bottom)
        }
    }

    #endif
}
