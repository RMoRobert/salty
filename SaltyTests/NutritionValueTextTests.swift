//
//  NutritionValueTextTests.swift
//  SaltyTests
//
//  The nutrition editor used to load fields with `Double.formatted()` (grouping on) and read them back
//  with `Double(text)`, so a sodium value of 1500 came back as nil and vanished on the next save. These
//  pin the round trip in a grouping locale and a comma-decimal one.
//

import Testing
import Foundation
import SaltyCore

@Suite("NutritionValueText")
struct NutritionValueTextTests {
    private let us = Locale(identifier: "en_US")
    private let de = Locale(identifier: "de_DE")

    @Test func showsThousandsWithoutGroupingSeparators() {
        #expect(NutritionValueText.text(for: 1500, locale: us) == "1500")
        #expect(NutritionValueText.text(for: 1500, locale: de) == "1500")
        #expect(NutritionValueText.text(for: 1_234_567, locale: us) == "1234567")
    }

    @Test func usesTheLocaleDecimalSeparator() {
        #expect(NutritionValueText.text(for: 1.5, locale: us) == "1.5")
        #expect(NutritionValueText.text(for: 1.5, locale: de) == "1,5")
        #expect(NutritionValueText.text(for: 240, locale: us) == "240")
        #expect(NutritionValueText.text(for: 0.125, locale: us) == "0.125")
        #expect(NutritionValueText.text(for: nil, locale: us) == "")
    }

    @Test func readsBackEverythingItShows() {
        for value in [0.0, 1.5, 240, 1500, 12_345.678] {
            for locale in [us, de] {
                let shown = NutritionValueText.text(for: value, locale: locale)
                #expect(NutritionValueText.value(from: shown, locale: locale) == value, "\(value) in \(locale.identifier) shown as \(shown)")
            }
        }
    }

    @Test func readsGroupedAndPlainInputByLocale() {
        #expect(NutritionValueText.value(from: "1,500", locale: us) == 1500)
        #expect(NutritionValueText.value(from: "1500", locale: us) == 1500)
        #expect(NutritionValueText.value(from: "1.5", locale: us) == 1.5)
        #expect(NutritionValueText.value(from: "1,5", locale: de) == 1.5)
        #expect(NutritionValueText.value(from: "1.500", locale: de) == 1500)
        #expect(NutritionValueText.value(from: "1500", locale: de) == 1500)
        // A plain keyboard number is accepted in any region.
        #expect(NutritionValueText.value(from: "1500.5", locale: de) == 1500.5)
        #expect(NutritionValueText.value(from: " 12 ", locale: us) == 12)
    }

    @Test func rejectsTextThatIsNotANumber() {
        #expect(NutritionValueText.value(from: "abc", locale: us) == nil)
        #expect(NutritionValueText.value(from: "12 g", locale: us) == nil)
        #expect(NutritionValueText.value(from: "", locale: us) == nil)
        #expect(NutritionValueText.isValid("abc", locale: us) == false)
        #expect(NutritionValueText.isValid("", locale: us) == true)
        #expect(NutritionValueText.isValid("   ", locale: us) == true)
        #expect(NutritionValueText.isValid("1,500", locale: us) == true)
        #expect(NutritionValueText.isValid("1,5", locale: de) == true)
    }
}
