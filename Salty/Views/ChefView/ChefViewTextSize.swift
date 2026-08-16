//
//  ChefViewTextSize.swift
//  Salty
//
//  Chef View's in-view text-size stepper. Default type tops out well below "legible from across the
//  kitchen", so the stepper reaches a long way past normal — but how it gets there differs by
//  platform, because only one of them has Dynamic Type:
//
//  - iOS/iPadOS: the steps are positions within Dynamic Type, reaching into the accessibility
//    sizes. The app's normal `.title2`/`.title3` fonts do the work, just resolved larger for the
//    Chef View subtree.
//  - macOS: there is no Dynamic Type, and `dynamicTypeSize` is inert there — so the stepper would
//    do nothing at all. Instead each text style is resolved to the system's own point size for it
//    and multiplied. The size still comes from the semantic style; it's only scaled.
//
//  Either way nothing here hard-codes a point size, which is what the "prefer Dynamic Type" rule
//  is protecting against. Use `chefFont(_:)` (ChefFontModifier) rather than `.font()` for anything
//  inside Chef View that should follow the stepper.
//

import SwiftUI
#if os(macOS)
import AppKit
#endif

enum ChefViewTextSize {
    static let storageKey = "chefViewTextSize"

    /// Stepper positions, smallest first. Starts at `.large` (the system default) rather than the
    /// smaller sizes — Chef View is never the place to shrink text below normal.
    static let levels: [DynamicTypeSize] = [
        .large, .xLarge, .xxLarge, .xxxLarge,
        .accessibility1, .accessibility2, .accessibility3, .accessibility4, .accessibility5,
    ]

    /// A step or two above normal seems like a good default to start with:
    static let defaultLevel = 2

    static var minimumLevel: Int { 0 }
    static var maximumLevel: Int { levels.count - 1 }

    static func clamped(_ level: Int) -> Int {
        min(max(level, minimumLevel), maximumLevel)
    }

    static func size(for level: Int) -> DynamicTypeSize {
        levels[clamped(level)]
    }

    /// For VoiceOver on the stepper buttons, which are otherwise just two unlabeled A's.
    static func accessibilityValue(for level: Int) -> String {
        "Text size \(clamped(level) + 1) of \(levels.count)"
    }

    #if os(macOS)

    /// One multiplier per entry in `levels`, tracking roughly how much iOS grows text across the
    /// same Dynamic Type steos (which don't apply on macOS, so this should try to simulate the different sizes)
    static let macScaleFactors: [CGFloat] = [1.0, 1.06, 1.12, 1.24, 1.4, 1.6, 1.9, 2.2, 2.5]

    static func macScaleFactor(for level: Int) -> CGFloat {
        macScaleFactors[clamped(level)]
    }

    /// A text style resolved at the stepper's current scale.
    static func font(_ style: Font.TextStyle, level: Int) -> Font {
        let baseSize = NSFont.preferredFont(forTextStyle: nsTextStyle(for: style)).pointSize
        return .system(size: baseSize * macScaleFactor(for: level))
    }

    private static func nsTextStyle(for style: Font.TextStyle) -> NSFont.TextStyle {
        switch style {
        case .largeTitle:   .largeTitle
        case .title:        .title1
        case .title2:       .title2
        case .title3:       .title3
        case .headline:     .headline
        case .subheadline:  .subheadline
        case .callout:      .callout
        case .footnote:     .footnote
        case .caption:      .caption1
        case .caption2:     .caption2
        default:            .body
        }
    }

    #endif
}
