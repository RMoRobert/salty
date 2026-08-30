//
//  ChefViewTextSizeTests.swift
//  SaltyTests
//
//  Chef View's sizing policy: the stepper's bounds, and how much text grows on an external display.
//  Both are pure arithmetic, which is the point — nothing here needs a view to check.
//

import Testing
import SwiftUI
@testable import Salty

@Suite
struct ChefViewTextSizeTests {

    @Test func stepperClampsToItsRange() {
        #expect(ChefViewTextSize.clamped(-5) == ChefViewTextSize.minimumLevel)
        #expect(ChefViewTextSize.clamped(99) == ChefViewTextSize.maximumLevel)
        #expect(ChefViewTextSize.clamped(2) == 2)
    }

    @Test func defaultLevelIsWithinTheStepperRange() {
        #expect(ChefViewTextSize.levels.indices.contains(ChefViewTextSize.defaultLevel))
    }

    #if !os(macOS)

    /// The two tables are indexed by the same stepper level, so a level added to one and not the
    /// other would resolve to the wrong size on an external display.
    @Test func contentSizeCategoriesCoverEveryStep() {
        #expect(ChefViewTextSize.contentSizeCategories.count == ChefViewTextSize.levels.count)
    }

    /// A phone- or iPad-sized canvas is left exactly as Dynamic Type made it.
    @Test func ordinaryDisplaysAreNotScaled() {
        #expect(ChefViewTextSize.externalDisplayScale(forWidth: 393) == 1)
        #expect(ChefViewTextSize.externalDisplayScale(forWidth: 960) == 1)
        #expect(ChefViewTextSize.externalDisplayScale(forWidth: 0) == 1, "before the first layout")
    }

    /// The size a mirrored TV normally reports, and the one the scale is really for.
    @Test func aTelevisionGetsRoughlyDoubleSizedText() {
        #expect(ChefViewTextSize.externalDisplayScale(forWidth: 1920) == 2)
    }

    @Test func scaleIsCappedForImplausiblyWideDisplays() {
        #expect(ChefViewTextSize.externalDisplayScale(forWidth: 7680) == 3)
    }

    /// The system-drawn placeholder can only be sized through Dynamic Type, so it steps up with the
    /// display instead of scaling smoothly with it.
    @Test func systemDrawnViewsStepUpWithTheDisplay() {
        #expect(ChefViewTextSize.externalDisplayTypeSize(forScale: 1) == .xLarge)
        #expect(ChefViewTextSize.externalDisplayTypeSize(forScale: 1.5) == .accessibility1)
        #expect(ChefViewTextSize.externalDisplayTypeSize(forScale: 2) == .accessibility3, "a TV")
    }

    /// Same style, same stepper position: only the display scale differs, and it multiplies.
    @Test func scalingGrowsTheResolvedStyle() {
        let normal = ChefViewTextSize.font(.title3, level: 2, scale: 1)
        let stretched = ChefViewTextSize.font(.title3, level: 2, scale: 2)

        #expect(normal != stretched)
    }

    #endif
}
