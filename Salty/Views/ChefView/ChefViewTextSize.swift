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
//  - An external display (iOS): Dynamic Type still applies, but it isn't enough on its own. A TV
//    hands the app a canvas around 1920 points wide, so type sized for a 400-point phone lands at
//    roughly half the size it should be — and even the largest accessibility size can't make up
//    the difference. There the resolved size is multiplied as well, by how much bigger the display
//    is than the one Chef View's sizes were chosen for (`externalDisplayScale(forWidth:)`).
//
//  Either way nothing here hard-codes a point size, which is what the "prefer Dynamic Type" rule
//  is protecting against. Use `chefFont(_:)` (ChefFontModifier) rather than `.font()` for anything
//  inside Chef View that should follow the stepper.
//

import SwiftUI
#if os(macOS)
import AppKit
#else
import UIKit
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

    #else

    // MARK: - External display

    /// The display width Chef View's own sizes are already right for — a large iPad, read from a
    /// step or two back. An external display is described relative to it, on the reasoning that
    /// text should occupy the same *fraction* of the screen there: a TV is both bigger and further
    /// away, and those two roughly cancel out.
    private static let referenceDisplayWidth: CGFloat = 960

    /// How much to stretch Chef View's text on an external display of the given point width.
    ///
    /// Never below 1, so a display no bigger than a phone's is left exactly as it is, and capped
    /// well above what any real TV reports so an odd width can't produce three words per screen.
    /// A 1920-point display — what a mirrored TV normally offers — comes out at 2×.
    static func externalDisplayScale(forWidth width: CGFloat) -> CGFloat {
        guard width > 0 else { return 1 }
        return min(max(width / referenceDisplayWidth, 1), 3)
    }

    /// A Dynamic Type size for the external display's system-drawn views — `ContentUnavailableView`
    /// and the like, which choose their own type and so have no `chefFont(_:)` to follow. Coarse on
    /// purpose: one size per rough class of display is enough for the handful of words involved.
    static func externalDisplayTypeSize(forScale scale: CGFloat) -> DynamicTypeSize {
        switch scale {
        case ..<1.25:   .xLarge
        case ..<1.75:   .accessibility1
        default:        .accessibility3
        }
    }

    /// A text style resolved to a point size for the stepper's current position, then stretched to
    /// the display. Used only where Dynamic Type alone can't get large enough (the external
    /// display); everywhere else `chefFont(_:)` leaves the sizing to Dynamic Type.
    ///
    /// Reaching into UIKit is what keeps the point size out of this file: `preferredFont` is asked
    /// what the style measures at that Dynamic Type size, exactly as the macOS path above asks
    /// AppKit.
    static func font(_ style: Font.TextStyle, level: Int, scale: CGFloat) -> Font {
        // The one-trait factory rather than `UITraitCollection(mutations:)`: the mutations closure
        // is main-actor isolated, and resolving a font size has no business needing the main actor.
        let traits = UITraitCollection(preferredContentSizeCategory: contentSizeCategory(for: level))
        let baseSize = UIFont.preferredFont(
            forTextStyle: uiTextStyle(for: style),
            compatibleWith: traits
        ).pointSize
        return .system(size: baseSize * scale)
    }

    /// The system content size category for each entry in `levels`, in the same order. Kept as its
    /// own table because `DynamicTypeSize` offers no conversion; ChefViewTextSizeTests checks the
    /// two stay the same length.
    static let contentSizeCategories: [UIContentSizeCategory] = [
        .large, .extraLarge, .extraExtraLarge, .extraExtraExtraLarge,
        .accessibilityMedium, .accessibilityLarge, .accessibilityExtraLarge,
        .accessibilityExtraExtraLarge, .accessibilityExtraExtraExtraLarge,
    ]

    private static func contentSizeCategory(for level: Int) -> UIContentSizeCategory {
        contentSizeCategories[clamped(level)]
    }

    private static func uiTextStyle(for style: Font.TextStyle) -> UIFont.TextStyle {
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
