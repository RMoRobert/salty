//
//  ChefIngredientsAnchor.swift
//  Salty
//
//  Where the external display should scroll its ingredient list to, as reported by the phone.
//
//  Not simply "the top-most row the phone is showing", because that alone can strand the end of the
//  list. Scrolling row N to the top of the TV shows N and whatever follows it *on that display* —
//  and the TV can hold fewer rows than the phone does (its text is around twice the size, and an
//  iPad's Chef View pane is full-height where the TV's has a header above it). A phone scrolled to
//  its last ingredient would then leave the last few unreachable on the TV, with nothing left to
//  scroll on either end.
//
//  So the ends are reported as ends. `.bottom` means "the phone has run out of list", which the TV
//  can always honour whatever it can fit; `.item` only ever describes somewhere in the middle.
//

import Foundation

enum ChefIngredientsAnchor: Equatable {
    /// The start of the list — also what a list too short to scroll reports, since a phone that
    /// can't scroll isn't expressing anything about where to look.
    case top
    /// Somewhere in the middle: this row goes to the top of the display.
    case item(index: Int)
    /// The end of the list, however much of it the display can show.
    case bottom
}
