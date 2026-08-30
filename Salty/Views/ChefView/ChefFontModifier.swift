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

extension EnvironmentValues {
    /// How much to stretch Chef View's text beyond the size the stepper asks for.
    ///
    /// 1 in the app itself, where Dynamic Type is the whole story. The external-display scene sets
    /// it once from the display's width (see ExternalChefDisplayView), because a TV's canvas is
    /// several times a phone's and normal type is lost on it.
    @Entry var chefFontScale: CGFloat = 1
}

private struct ChefFontModifier: ViewModifier {
    let style: Font.TextStyle

    @AppStorage(ChefViewTextSize.storageKey) private var textSizeLevel = ChefViewTextSize.defaultLevel
    @Environment(\.chefFontScale) private var fontScale

    func body(content: Content) -> some View {
        content.font(font)
    }

    private var font: Font {
        #if os(macOS)
        ChefViewTextSize.font(style, level: textSizeLevel)
        #else
        if fontScale > 1 {
            // An external display. Dynamic Type runs out well before "legible from the sofa", so
            // the style is resolved to a size here and stretched to the display instead.
            ChefViewTextSize.font(style, level: textSizeLevel, scale: fontScale)
        } else {
            // The style alone; ChefView sets `dynamicTypeSize` on the whole content subtree, and
            // that's what resolves this larger or smaller. Design (rounded) comes from the container.
            .system(style)
        }
        #endif
    }
}

extension View {
    func chefFont(_ style: Font.TextStyle) -> some View {
        modifier(ChefFontModifier(style: style))
    }
}
