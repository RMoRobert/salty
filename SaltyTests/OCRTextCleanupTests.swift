//
//  OCRTextCleanupTests.swift
//  SaltyTests
//

import Testing
import SaltyCore

struct OCRTextCleanupTests {

    @Test func fixesCapitalIReadAsLInPounds() {
        #expect(OCRTextCleanup.apply(to: "2 Ibs chicken thighs") == "2 lbs chicken thighs")
        #expect(OCRTextCleanup.apply(to: "1 Ib butter") == "1 lb butter")
        #expect(OCRTextCleanup.apply(to: "1Ib butter") == "1lb butter")
    }

    @Test func fixesZeroReadAsOInOunces() {
        #expect(OCRTextCleanup.apply(to: "8 0z cream cheese") == "8 oz cream cheese")
    }

    @Test func fixesLowercaseLReadAsOneInFractionsAndQuantities() {
        #expect(OCRTextCleanup.apply(to: "l/2 cup sugar") == "1/2 cup sugar")
        #expect(OCRTextCleanup.apply(to: "I/4 tsp salt") == "1/4 tsp salt")
        #expect(OCRTextCleanup.apply(to: "l cup flour\nI tbsp oil") == "1 cup flour\n1 tbsp oil")
    }

    @Test func leavesProseAlone() {
        let prose = "I love Ibiza. Add the 0-zero mixture. Ib is not a word here: Ibsen wrote plays."
        #expect(OCRTextCleanup.apply(to: prose) == prose)
        #expect(OCRTextCleanup.apply(to: "I like it with 2 cups") == "I like it with 2 cups")
    }
}
