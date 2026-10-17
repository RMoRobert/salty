//
//  SaltyURLTests.swift
//  SaltyTests
//
//  The salty:// link grammar: what parses, what is refused, and that a built link reads back as
//  the request it was built from.
//

import Testing
import Foundation
@testable import Salty

struct SaltyURLTests {
    private func parse(_ text: String) -> SaltyURL? {
        guard let url = URL(string: text) else { return nil }
        return SaltyURL(url)
    }

    // MARK: - Import

    @Test func importLinkWithEncodedAddress() {
        let link = parse("salty://import?url=https%3A%2F%2Fexample.com%2Fpie%3Fa%3D1%26b%3D2")
        #expect(link == .importFromWeb(URL(string: "https://example.com/pie?a=1&b=2")!))
    }

    @Test func importLinkWithPlainAddressStillParses() {
        // Hand-typed links usually aren't encoded; a page address without `&` or `#` survives that.
        let link = parse("salty://import?url=https://example.com/recipes/pie/")
        #expect(link == .importFromWeb(URL(string: "https://example.com/recipes/pie/")!))
    }

    @Test func importLinkAssumesHTTPSWhenSchemeIsMissing() {
        #expect(parse("salty://import?url=example.com/pie") == .importFromWeb(URL(string: "https://example.com/pie")!))
    }

    @Test func importLinkAcceptsHTTP() {
        #expect(parse("salty://import?url=http://example.com/pie") == .importFromWeb(URL(string: "http://example.com/pie")!))
    }

    @Test(arguments: [
        "salty://import",                                   // no address
        "salty://import?url=",                              // empty address
        "salty://import?url=%20%20",                        // blank address
        "salty://import?url=file:///etc/passwd",            // not a web page
        "salty://import?url=javascript:alert(1)",           // not a web page
        "salty://import?url=https://",                      // no host
        "salty://import?page=https://example.com"           // wrong parameter name
    ])
    func importLinkRefusesNonWebAddresses(_ text: String) {
        #expect(parse(text) == nil)
    }

    // MARK: - Recipe

    @Test func recipeLink() {
        #expect(parse("salty://recipe/0199C7A2-5F3E-7A1B-9C4D-2E6F8A0B1C3D") == .recipe(id: "0199C7A2-5F3E-7A1B-9C4D-2E6F8A0B1C3D"))
    }

    @Test(arguments: [
        "salty://recipe",               // no id
        "salty://recipe/",              // empty id
        "salty://recipe/abc/extra",     // more than an id
        "salty://recipe?id=abc"         // id in the wrong place
    ])
    func recipeLinkRequiresExactlyOneId(_ text: String) {
        #expect(parse(text) == nil)
    }

    // MARK: - Shape

    @Test func schemeAndHostAreCaseInsensitive() {
        #expect(parse("SALTY://Import?url=https://example.com") == .importFromWeb(URL(string: "https://example.com")!))
        #expect(parse("Salty://RECIPE/abc") == .recipe(id: "abc"))
    }

    @Test(arguments: [
        "https://example.com/recipe",   // not our scheme
        "salty://",                     // no request
        "salty:///",                    // no request, three-slash form
        "salty://unknown/abc",          // no such request
        "salty-recipe://import?url=https://example.com"
    ])
    func otherLinksAreNotOurs(_ text: String) {
        #expect(parse(text) == nil)
    }

    /// The `salty:///verb` spelling (no host; Things and OmniFocus write their links this way) reads
    /// the same as `salty://verb`.
    @Test func threeSlashFormIsEquivalent() {
        #expect(parse("salty:///import?url=https://example.com/pie") == .importFromWeb(URL(string: "https://example.com/pie")!))
        #expect(parse("salty:///recipe/abc") == .recipe(id: "abc"))
        #expect(parse("salty:///recipe") == nil)
        #expect(parse("salty:///recipe/abc/extra") == nil)
    }

    // MARK: - Round trip

    @Test func builtImportLinkReadsBack() {
        // The nested address has every character that would break an unencoded query: `&`, `=`, `#`.
        let page = URL(string: "https://example.com/r?a=1&b=2#step-3")!
        let link = SaltyURL.importFromWeb(page)
        #expect(link.url.scheme == "salty")
        #expect(SaltyURL(link.url) == link)
    }

    @Test func builtRecipeLinkReadsBack() {
        let link = SaltyURL.recipe(id: "0199C7A2-5F3E-7A1B-9C4D-2E6F8A0B1C3D")
        #expect(link.url.absoluteString == "salty://recipe/0199C7A2-5F3E-7A1B-9C4D-2E6F8A0B1C3D")
        #expect(SaltyURL(link.url) == link)
    }
}
