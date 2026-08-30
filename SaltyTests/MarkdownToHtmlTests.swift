//
//  MarkdownToHtmlTests.swift
//  SaltyTests
//
//  Covers Salty's wiring around swift-markdown's HTMLFormatter — that a freeform list renders the
//  block elements shopping lists rely on, that the document is themeable, and that user text can't
//  break out of the markup. Not a test of the library's own Markdown conformance.
//

import Testing
import SaltyCore
@testable import Salty

struct MarkdownToHtmlTests {

    @Test func rendersHeadingsAndBullets() {
        let html = MarkdownToHtml.document(markdown: "# Produce\n\n* Apples\n* Spinach")
        #expect(html.contains("<h1>Produce</h1>"))
        #expect(html.contains("<ul>"))
        // HTMLFormatter has no tight-list special case — item content is always wrapped in <p>.
        // The Markdown CSS zeroes those margins so the list still reads tight.
        #expect(html.contains("<li><p>Apples</p>"))
    }

    /// Task items must share a line with their checkbox, and in a mixed list the boxes must land in
    /// the marker column (aligned with bullets) while the text stays on the normal content edge
    /// (aligned with the other items' text). Both fall out of taking the box out of flow: HTMLFormatter
    /// puts item text in a `<p>`, and a block-level `<p>` would drop below an in-flow inline checkbox.
    @Test func taskCheckboxesArePositionedInTheMarkerColumn() {
        let html = MarkdownToHtml.document(markdown: "- Bullet\n- [ ] Checkbox item")
        #expect(html.contains(#"li:has(> input[type="checkbox"])"#))
        #expect(html.contains("position: absolute"))
        // The negative inset pulls the box out into the marker area. Measured in WebKit so the box's
        // center lands on the bullet's center (matching left edges reads as too far right).
        #expect(html.contains("left: -1.8em"))
    }

    @Test func rendersTaskCheckboxes() {
        let html = MarkdownToHtml.document(markdown: "* [x] Apples\n* [ ] Spinach")
        // Checked and unchecked boxes are both disabled (the preview is read-only).
        #expect(html.contains(#"<input type="checkbox" disabled="" checked="" />"#))
        #expect(html.contains(#"<input type="checkbox" disabled="" />"#))
    }

    @Test func rendersInlineEmphasis() {
        let html = MarkdownToHtml.document(markdown: "the **good** ones and *sales*")
        #expect(html.contains("<strong>good</strong>"))
        #expect(html.contains("<em>sales</em>"))
    }

    @Test func rendersTablesAndCodeBlocks() {
        // Block elements the previous hand-rolled renderer could not handle.
        let table = MarkdownToHtml.document(markdown: "| Item | Qty |\n| --- | --- |\n| Milk | 2 |")
        #expect(table.contains("<table>"))
        #expect(table.contains("<td>Milk</td>"))

        let code = MarkdownToHtml.document(markdown: "```\nplain\n```")
        #expect(code.contains("<pre>"))
    }

    // MARK: - Untrusted-content hardening
    //
    // List text is untrusted (imports, shared files, the sync server — see RecipeHtmlEscapingTests).
    // Markdown allows embedded HTML by design and HTMLFormatter emits it verbatim, so the safety
    // guarantee is enforced by the document's Content-Security-Policy rather than by escaping.

    @Test func documentCarriesALockedDownContentSecurityPolicy() {
        let html = MarkdownToHtml.document(markdown: "# Hi")
        #expect(html.contains(#"<meta http-equiv="Content-Security-Policy""#))
        // Blocks scripts, frames and network fetches, and inline event handlers like onerror=.
        #expect(MarkdownToHtml.contentSecurityPolicy.contains("default-src 'none'"))
        // Remote images would act as tracking beacons; inline data: images stay allowed.
        #expect(MarkdownToHtml.contentSecurityPolicy.contains("img-src data:"))
        #expect(!MarkdownToHtml.contentSecurityPolicy.contains("script-src"))
    }

    @Test func cspIsPresentWheneverUntrustedMarkupCouldBeEmitted() throws {
        // The CSP must accompany the payload in the same document, not just the empty case, and it
        // has to precede the content it governs.
        let html = MarkdownToHtml.document(markdown: "buy <script>alert('x')</script> now")
        let cspIndex = try #require(html.range(of: "Content-Security-Policy")?.lowerBound)
        let bodyIndex = try #require(html.range(of: "<body>")?.lowerBound)
        #expect(cspIndex < bodyIndex)
    }

    /// Pins swift-markdown 0.8.0's actual behavior: raw HTML — and even plain text — is emitted
    /// unescaped (`visitText` appends `text.string` as-is; `htmlEscaped()` doesn't exist in 0.8.0 and
    /// was only added later on an unreleased `main`). This is exactly why the CSP above is required.
    ///
    /// If this test starts failing after a swift-markdown upgrade, that's good news — the formatter
    /// began escaping. Keep the CSP regardless, but the comments in `MarkdownToHtml` explaining why
    /// escaping-based defenses were rejected should then be revisited.
    @Test func rawHtmlPassesThroughUnescaped_documentingWhyTheCSPIsRequired() {
        let html = MarkdownToHtml.bodyHTML(markdown: "buy <script>alert('x')</script> now")
        #expect(html.contains("<script>"))
        #expect(!html.contains("&lt;script&gt;"))
    }

    @Test func producesACompleteDocument() {
        let html = MarkdownToHtml.document(markdown: "# Hi")
        #expect(html.hasPrefix("<!DOCTYPE html>"))
        #expect(html.contains("<h1>Hi</h1>"))
        #expect(html.hasSuffix("</html>"))
    }

    @Test func stylingStaysMinimalAndUsesTheSystemFont() {
        let html = MarkdownToHtml.document(markdown: "# Hi")
        // WebKit's default body font is Times, so the system font is set explicitly...
        #expect(html.contains("font-family: system-ui"))
        // ...and the system appearance is adopted so default colors flip in dark mode.
        #expect(html.contains("color-scheme: light dark"))
        // Otherwise the browser's own default stylesheet is left alone — the recipe themes are
        // deliberately not applied here (see MarkdownToHtml).
        #expect(!html.contains("--salty-page-bg"))
        #expect(!html.contains("normalize.css"))
    }

    @Test func emptyMarkdownStillProducesAValidDocument() {
        let html = MarkdownToHtml.document(markdown: "")
        #expect(html.hasPrefix("<!DOCTYPE html>"))
        #expect(html.contains("</html>"))
    }

    @Test func rendersWhatTheConverterWrites() {
        // Freeform text produced by a structured→freeform conversion must render correctly.
        let items = [
            ShoppingListListContents(id: "h1", isHeading: true, text: "Produce"),
            ShoppingListListContents(id: "i1", text: "apples"),
            ShoppingListListContents(id: "i2", isCompleted: true, text: "bananas"),
        ]
        let html = MarkdownToHtml.document(markdown: ShoppingListFreeformConverter.text(from: items))
        #expect(html.contains("<h1>Produce</h1>"))
        #expect(html.contains("apples"))
        #expect(html.contains(#"checked="""#))
    }
}
