//
//  RecipeRowFocus.swift
//  Salty
//
//  Puts the keyboard into a row that was just added.
//
//  The row doesn't exist yet when the append returns -- SwiftUI hasn't processed the change, so there
//  is nothing for `focused(_:equals:)` to match against. Focus has to wait for the next layout pass.
//  The macOS editors do this inline; this handles rows in iOS all in one place. The sleep timer is a bit
//  hack-y but the best workaround I can think of for now...
//

import SwiftUI

enum RecipeRowFocus {

    /// Focuses the row with `id` once it has been laid out.
    @MainActor
    static func focus(_ id: String, in focus: FocusState<String?>.Binding) {
        Task {
            try? await Task.sleep(for: .seconds(0.05))
            focus.wrappedValue = id
        }
    }
}
