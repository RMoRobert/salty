//
//  SyncProgressTextTests.swift
//  SaltyTests
//
//  The Apple app's wording for values SaltyCore now reports without words: sync steps and counts, and
//  the grammar-agreement helper behind every count.
//

import Testing
import Foundation
@testable import Salty
import SaltyCore

struct SyncProgressTextTests {
    @Test func countsAgreeWithTheirNumbers() {
        var progress = SyncProgress()
        progress.itemsUploaded = 1
        progress.imagesUploaded = 2
        #expect(progress.countsSummary == "↑ 1 item, 2 images | ↓ 0 items, 0 images")
        progress.imagesFailed = 1
        #expect(progress.countsSummary.hasSuffix(" | 1 image failed"))
    }

    @Test func everyStepButIdleHasALabel() {
        for step in SyncProgress.Step.allCases where step != .idle {
            #expect(!step.label.isEmpty, "\(step)")
        }
    }

    @Test func inflectedStringsDropTheMarkup() {
        #expect(String(inflected: "^[\(1) serving](inflect: true)") == "1 serving")
        #expect(String(inflected: "^[\(4) serving](inflect: true)") == "4 servings")
    }
}
