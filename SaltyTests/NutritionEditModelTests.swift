//
//  NutritionEditModelTests.swift
//  SaltyTests
//
//  The nutrition editor's rules, now that they are a value rather than view state: amounts round-trip
//  through the user's locale, a field that isn't a number is flagged and stored as nothing, a blank
//  editor stores nil, and an untouched editor is not a change.
//

import Testing
import Foundation
import SaltyCore

@Suite("NutritionEditModel")
struct NutritionEditModelTests {
    private let us = Locale(identifier: "en_US")
    private let de = Locale(identifier: "de_DE")

    private var sample: NutritionInformation {
        NutritionInformation(id: "nut-1", servingSize: "1 cup", calories: 1500, protein: 12.5, sodium: 2300)
    }

    @Test func showsAmountsWithoutGroupingAndReadsThemBack() throws {
        var model = NutritionEditModel(sample, locale: us)
        #expect(model[.calories] == "1500")
        #expect(model[.protein] == "12.5")
        #expect(model[.fat] == "")
        #expect(model.servingSize == "1 cup")

        model[.calories] = "1,750"
        model[.fat] = "3"
        let stored = try #require(model.nutrition)
        #expect(stored.calories == 1750, "a typed grouping separator is read by the locale")
        #expect(stored.fat == 3)
        #expect(stored.protein == 12.5)
        #expect(stored.id == "nut-1", "the stored value keeps its identity")
    }

    @Test func germanTextsUseTheGermanDecimalSeparator() {
        var model = NutritionEditModel(sample, locale: de)
        #expect(model[.protein] == "12,5")
        model[.fat] = "1,5"
        #expect(model.value(of: .fat) == 1.5)
    }

    @Test func aFieldThatIsNotANumberIsFlaggedAndStoresNothing() {
        var model = NutritionEditModel(sample, locale: us)
        model[.sodium] = "lots"
        #expect(!model.isValid(.sodium))
        #expect(model.invalidFields == [.sodium])
        #expect(model.hasInvalidFields)
        #expect(model.nutrition?.sodium == nil)

        model[.sodium] = ""
        #expect(model.isValid(.sodium), "blank is allowed")
        #expect(!model.hasInvalidFields)
    }

    @Test func blankEditorStoresNil() {
        var model = NutritionEditModel(sample, locale: us)
        #expect(!model.isBlank)
        model.servingSize = "  "
        for field in NutritionEditModel.Field.allCases {
            model[field] = ""
        }
        #expect(model.isBlank)
        #expect(model.nutrition == nil)
        #expect(model.hasChanges)

        let empty = NutritionEditModel(nil, locale: us)
        #expect(empty.isBlank)
        #expect(empty.nutrition == nil)
        #expect(!empty.hasChanges)
    }

    @Test func untouchedEditorIsNotAChange() {
        var model = NutritionEditModel(sample, locale: us)
        #expect(!model.hasChanges)
        model[.protein] = "12.50"
        #expect(!model.hasChanges, "the same amount written differently is not a change")
        model[.protein] = "13"
        #expect(model.hasChanges)
    }

    @Test func everyFieldHasASectionAndTheSectionsCoverEveryField() {
        let filed = NutritionEditModel.Section.allCases.flatMap(\.fields)
        #expect(Set(filed) == Set(NutritionEditModel.Field.allCases))
        #expect(filed.count == NutritionEditModel.Field.allCases.count)
        #expect(NutritionEditModel.Field.calories.unit == nil)
        #expect(NutritionEditModel.Field.vitaminD.unit == .micrograms)
    }
}
