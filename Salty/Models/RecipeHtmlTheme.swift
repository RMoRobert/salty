//
//  RecipeHtmlTheme.swift
//  Salty
//
//  A theme is just CSS appended after the base recipe stylesheet (see RecipeToHtml's "Theming" note).
//  Built-in themes live here; a future user theme would supply its own `overrideCSS` (e.g. read from a
//  user-selected .css file). Themes override the `:root` --salty-* variables and/or the stable
//  selectors documented in RecipeToHtml.
//

import Foundation

enum RecipeHtmlTheme: String, CaseIterable, Identifiable, Codable {
    case modern
    case retro

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .modern: return "Modern"
        case .retro:  return "Retro Aquatic"
        }
    }

    /// CSS appended after the base stylesheet. Empty = the built-in default look.
    var overrideCSS: String {
        switch self {
        case .modern: return ""
        case .retro:  return Self.retroCSS
        }
    }

    // Aquatic palette in a "Cosmopolitan"-style magazine layout (à la MacGourmet): a flat light-blue
    // page, a muted slate title, image + ingredients in a left column, intro + directions on the right,
    // metadata beneath the directions, and notes in a bordered card.
    //
    // The colors/fonts apply on screen AND in print (so printouts match the view). The two-column REFLOW
    // is screen-only and gated at the same 750px breakpoint the base stylesheet uses, so narrow screens
    // and print fall back to the base single-column layout. The reflow works without touching the base
    // HTML: `display: contents` dissolves the wrapper boxes (#recipe-info-container and its
    // .recipe-content-area) so the title, image, and metadata become direct grid items of `main` and can
    // be placed individually. Selectors here are the stable IDs/classes documented in RecipeToHtml.
    private static let retroCSS = """
    :root {
        --salty-font-body: "Lucida Grande", "Lucida Sans Unicode", Geneva, Verdana, sans-serif;
        --salty-font-heading: "Lucida Grande", "Lucida Sans Unicode", Geneva, sans-serif;
        --salty-page-bg: #dfeaf2;
        --salty-surface: #eef4f9;
        --salty-panel-bg: #e7eef5;
        --salty-text: #33414f;
        --salty-text-secondary: #5d6b78;
        --salty-heading: #5f7180;
        --salty-accent: #3f74a3;
        --salty-link: #2f6aa8;
        --salty-link-hover: #4a90d9;
        --salty-border: #b8c9d8;
        --salty-star-filled: #6b7b88;
        --salty-card-radius: 8px;
        --salty-card-shadow: 0 2px 8px rgba(0, 0, 0, 0.16);
    }

    body { font-family: var(--salty-font-body) !important; }

    /* Big muted-slate title instead of the modern gradient text. */
    #recipe-name {
        background: none !important;
        -webkit-background-clip: border-box !important;
        background-clip: border-box !important;
        -webkit-text-fill-color: currentColor !important;
        color: var(--salty-heading) !important;
        font-weight: 600 !important;
    }

    h2 { color: var(--salty-accent) !important; }
    .recipe-directions-step-number { color: var(--salty-accent) !important; font-weight: 700 !important; }
    .recipe-ingredient::before { color: var(--salty-accent) !important; }

    /* Flat, borderless sections — the Cosmopolitan look is airy, not glassy/boxed. The notes card keeps
       its border (set below); tag/category chips keep theirs. */
    #recipe-info-container,
    #recipe-introduction-container,
    #recipe-ingredients-container,
    #recipe-directions-container,
    #recipe-variations-container,
    #recipe-meta-container,
    #recipe-image,
    #recipe-prep-time-list li,
    #recipe-yield-item,
    #recipe-servings-item {
        border: none !important;
        background: none !important;
        box-shadow: none !important;
    }

    @media screen {
        /* Aqua-inspired vertical gradient: a near-white blue at the top easing into a soft Aqua blue.
           Fixed attachment keeps it steady while scrolling and consistent for short or long recipes. The
           base white "card" backgrounds on the page wrappers are dropped so the content sits on the wash.
           html carries the end color for the area beyond the centered body. */
        html { background: #d2e4f1 !important; }
        body {
            background-color: #d2e4f1 !important;
            background-image: linear-gradient(180deg, #f7fbfe 0%, #e4eff8 50%, #d2e4f1 100%) !important;
            background-attachment: fixed !important;
            color: var(--salty-text) !important;
        }
        main { background: transparent !important; padding: 2.5rem 1.75rem !important; }
    }

    /* The two-column magazine reflow — screen only, wide viewports only (matches the base breakpoint). */
    @media screen and (min-width: 750px) {
        /* Dissolve the wrapper boxes so their children join the `main` grid directly. */
        #recipe-info-container,
        #recipe-info-container .recipe-content-area { display: contents !important; }

        main {
            grid-template-columns: 36% 1fr !important;
            column-gap: 3rem !important;
            row-gap: 0.4rem !important;
            align-items: start !important;
            /* Generous magazine margins on desktop. */
            padding: 5.5rem 6rem !important;
        }

        /* Title spans the full width on top. */
        #recipe-name { grid-column: 1 / -1 !important; grid-row: 1 !important; margin: 0 0 0.4em 0 !important; }

        /* Left column: image, ingredients, then yield/servings + rating beneath. */
        #recipe-image-container       { grid-column: 1 !important; grid-row: 2 !important; }
        #recipe-ingredients-container { grid-column: 1 !important; grid-row: 3 !important; align-self: start !important; }
        .recipe-yield-and-servings-container { grid-column: 1 !important; grid-row: 4 !important; margin-top: 0.6rem !important; }
        #recipe-rating-star-container { grid-column: 1 !important; grid-row: 5 !important; }
        #recipe-difficulty-container  { grid-column: 1 !important; grid-row: 6 !important; }

        /* Right column: intro, directions, then source / prep / categories. */
        #recipe-introduction-container { grid-column: 2 !important; grid-row: 2 !important; }
        #recipe-directions-container   { grid-column: 2 !important; grid-row: 3 !important; align-self: start !important; }
        #recipe-source           { grid-column: 2 !important; grid-row: 4 !important; }
        #recipe-sourceDetails    { grid-column: 2 !important; grid-row: 5 !important; }
        #recipe-course-container { grid-column: 2 !important; grid-row: 6 !important; }
        #recipe-prep-time-container { grid-column: 2 !important; grid-row: 7 !important; }
        #recipe-meta-container      { grid-column: 2 !important; grid-row: 8 !important; }

        /* Notes / variations span full width at the bottom. Explicit rows below all the content
           (which tops out at row 8) so they never auto-place into an empty upper row — e.g. when a
           recipe has no image and no introduction, leaving row 2 free. */
        #recipe-notes-container      { grid-column: 1 / -1 !important; grid-row: 9 !important; }
        #recipe-variations-container { grid-column: 1 / -1 !important; grid-row: 10 !important; }

        /* The "3/5" numeric rating is redundant with the stars in this layout. */
        #recipe-rating-raw-container { display: none !important; }

        /* A hairline rule above the right-column metadata, separating it from the last direction. */
        #recipe-source {
            border-top: 1px solid var(--salty-border) !important;
            margin-top: 1.4rem !important;
            padding-top: 1rem !important;
        }
    }

    #recipe-image {
        box-shadow: var(--salty-card-shadow) !important;
        max-width: 100% !important;
        width: 100% !important;
        height: auto !important;
    }

    /* Notes as a simple bordered card. */
    #recipe-notes-container { border-top: 1px solid var(--salty-border) !important; padding-top: 1rem !important; margin-top: 1.5rem !important; }
    .recipe-note-container {
        border: 1px solid var(--salty-border) !important;
        border-radius: var(--salty-card-radius) !important;
        background: rgba(255, 255, 255, 0.45) !important;
        padding: 0.9rem 1.1rem !important;
    }
    /* Space between a note's title and its body text. */
    .recipe-note-heading { margin-bottom: 0.45rem !important; }
    """
}
