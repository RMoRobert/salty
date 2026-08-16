//
//  ChefFontModifier.swift
//  Salty
//
//  `chefFont(_:)` — use this instead of `.font()` for any text inside Chef View that should follow
//  the in-view text-size stepper. It picks the right mechanism per platform (see ChefViewTextSize):
//  Dynamic Type on iOS, scaled semantic sizes on macOS, which has no Dynamic Type at all.
//
//  Chrome that should stay a normal, predictable size — the header bar, the controls bar — keeps
//  using plain `.font()`.
//

import SwiftUI

private struct ChefFontModifier: ViewModifier {
    let style: Font.TextStyle

    @AppStorage(ChefViewTextSize.storageKey) private var textSizeLevel = ChefViewTextSize.defaultLevel

    func body(content: Content) -> some View {
        #if os(macOS)
        content.font(ChefViewTextSize.font(style, level: textSizeLevel))
        #else
        // The style alone; ChefView sets `dynamicTypeSize` on the whole content subtree, and that's
        // what resolves this larger or smaller. Design (rounded) still comes from the container.
        content.font(.system(style))
        #endif
    }
}

extension View {
    func chefFont(_ style: Font.TextStyle) -> some View {
        modifier(ChefFontModifier(style: style))
    }
}
