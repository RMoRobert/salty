//
//  SchemaOrgRecipeJSONLDImporterShapeTests.swift
//  SaltyTests
//
//  JSON-LD page shapes are pinned by salty-contract's `webimport` corpus (see ContractCorpusTests).
//  This covers what the corpus can't: a draft's random ids and dates (WEB-031), and the bare-JSON-LD
//  entry point, which is this API's rather than the contract's.
//

import Testing
import Foundation
import SaltyCore

struct SchemaOrgRecipeJSONLDImporterShapeTests {

    private let importer = SchemaOrgRecipeJSONLDImporter()

    /// Every id is minted here and the recipe is a draft with no history (WEB-031).
    @Test func mintsIdsAndLeavesTheRecipeUnstored() throws {
        let html = #"<script type="application/ld+json">{"@type":"Recipe","@id":"https://example.com/#r","name":"R","recipeIngredient":["1 egg"],"recipeInstructions":["Beat it"]}</script>"#
        let recipe = try #require(importer.parseRecipes(from: html).first)

        #expect(!recipe.id.isEmpty)
        #expect(recipe.id == recipe.id.uppercased())
        #expect(recipe.id != "https://example.com/#r", "nothing from the page becomes an id")
        #expect(recipe.ingredients.first?.id != recipe.id)
        #expect(recipe.directions.first?.id != recipe.ingredients.first?.id)
        #expect(recipe.imageFilename == nil)
        #expect(recipe.rating == .notSet)
        #expect(recipe.difficulty == .notSet)
        #expect(!recipe.isFavorite)
        #expect(abs(recipe.createdDate.timeIntervalSinceNow) < 60)
        #expect(recipe.createdDate == recipe.createdDate.roundedToWireMillis, "whole milliseconds, like every SaltyCore stamp")
        #expect(recipe.lastModifiedDate == recipe.createdDate)
    }

    @Test func parsesBareJsonLdWithNoPageAroundIt() {
        let scanned = importer.scanJSONLD(Data(#"{"@type":"Recipe","name":"Bare","image":"b.jpg"}"#.utf8), pageURL: "https://example.com/r/")
        #expect(scanned.map(\.recipe.name) == ["Bare"])
        #expect(scanned.first?.imageURL == "https://example.com/r/b.jpg", "relative addresses resolve against the page here too")
    }
}
