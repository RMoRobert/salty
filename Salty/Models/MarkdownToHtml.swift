//
//  MarkdownToHtml.swift
//  Salty
//
//  Created by Robert on 7/25/26.
//

import Foundation
import Markdown

/// Renders user-authored Markdown (freeform shopping lists) to an HTML document for display in a web
/// view.
///
/// Parsing/serialization is Apple's `swift-markdown` (`HTMLFormatter`), so the supported syntax is
/// full CommonMark + GFM — headings, ordered/unordered lists, task checkboxes, tables, code blocks,
/// block quotes, strikethrough — rather than a hand-rolled subset.
///
/// Styling is deliberately minimal: the browser's own default stylesheet, plus only the few rules it
/// can't reasonably be expected to get right (WebKit defaults to Times, and `HTMLFormatter` emits
/// markup that needs two small corrections — see `baseCSS`). Applying the recipe themes here instead
/// (`getDefaultCSS()` + `RecipeHtmlTheme.overrideCSS`, the way `RecipeToHtml` does) remains an easy
/// future option: append that CSS after `baseCSS` so it wins.
enum MarkdownToHtml {

    /// A complete, self-contained HTML document for the given Markdown.
    static func document(markdown: String) -> String {
        """
        <!DOCTYPE html>
        <html>
        <head>
        <meta charset="utf-8">
        <meta http-equiv="Content-Security-Policy" content="\(contentSecurityPolicy)">
        <meta name="viewport" content="width=device-width, initial-scale=1.0">
        <style>
        \(baseCSS)
        </style>
        </head>
        <body>
        \(bodyHTML(markdown: markdown))
        </body>
        </html>
        """
    }

    /// The rendered body contents for the given Markdown.
    static func bodyHTML(markdown: String) -> String {
        HTMLFormatter.format(markdown)
    }

    /// Locks the rendered document down so untrusted list text can't do anything but display.
    ///
    /// Necessary because Markdown deliberately allows embedded HTML, and `HTMLFormatter` emits it
    /// verbatim. In swift-markdown 0.8.0, it doesn't even escape plain text nodes (`visitText`
    /// appends `text.string` unmodified). List text is untrusted for the same reasons recipe text is
    /// (imports, shared files, the sync server;  see `RecipeHtmlEscapingTests`), and neither
    /// sanitizing the parsed tree nor pre-escaping the source is a working defense here: rewriting
    /// raw-HTML nodes to text doesn't help when text isn't escaped either, and pre-escaping is undone
    /// by the parser's HTML-entity decoding (`&lt;b&gt;` parses back to a live `<b>`) while also
    /// corrupting real Markdown like `>` block quotes.
    ///
    /// So the guarantee is enforced at the document level instead, which holds no matter what the
    /// formatter emits: `default-src 'none'` blocks scripts, frames, and network fetches, and CSP
    /// also blocks inline event handlers such as `onerror=`; `img-src data:` permits inline images
    /// while blocking remote ones (which would otherwise act as tracking beacons). Inline styling
    /// stays allowed because the stylesheet below is inline. The residual effect of embedded HTML is
    /// therefore cosmetic: `<b>` renders bold, which is standard Markdown behavior.
    static let contentSecurityPolicy = "default-src 'none'; style-src 'unsafe-inline'; img-src data:;"

    /// Everything the browser's default stylesheet doesn't already handle well, and nothing more.
    private static let baseCSS = """
    /* Simple styling for something slightly better than browser defaults */
    :root { color-scheme: light dark; }

    body {
        font-family: system-ui, sans-serif;
        line-height: 1.1;
        margin: 0 auto;
        max-width: 45rem;
        padding: 0.5rem 0.5rem;
    }

    /* HTMLFormatter wraps every list item's content in <p>; drop its block margins so a simple list
       doesn't appear double-spaced */
    li > p { margin: 0; }

    /* Lift checkbox out flow and plac in the list's marker area (to replace bullet) so all lines
       up, no line break, etc. */
    li:has(> input[type="checkbox"]) {
        list-style: none;
        position: relative;
    }
    li:has(> input[type="checkbox"]) > input[type="checkbox"] {
        position: absolute;
        /* Centers the box on the bullet's own center rather than lining up their left edges; probably a 
           better way to do, this, but lines up with WebKit default rendering on platforms tested... */
        left: -1.8em;
        top: 0.2em;
        margin: 0;
    }
    """
}
