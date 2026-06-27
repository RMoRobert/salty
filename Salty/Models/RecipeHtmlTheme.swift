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

    // Early Mac OS X "Aqua": Lucida Grande, cool grays, glassy blue accents. Scoped to @media screen
    // so the carefully-tuned print layout in the base stylesheet is unaffected by the chosen theme.
    private static let retroCSS = """
    /* Theme identity (fonts + colors) — applies on screen AND in print so printouts match the view.
       The base print stylesheet still owns the page layout (margins, breaks, white paper). */
    :root {
        --salty-font-body: "Lucida Grande", "Lucida Sans Unicode", Geneva, Verdana, sans-serif;
        --salty-font-heading: "Lucida Grande", "Lucida Sans Unicode", Geneva, sans-serif;
        --salty-page-bg: #d6dde6;
        --salty-surface: #ffffff;
        --salty-panel-bg: #eef3f9;
        --salty-text: #1a1a1a;
        --salty-text-secondary: #4b5566;
        --salty-heading: #1b3a6b;
        --salty-accent: #2b7bea;
        --salty-link: #1a5fb4;
        --salty-link-hover: #2b7bea;
        --salty-border: #9fb0c3;
        --salty-star-filled: #f5b400;
        --salty-card-radius: 10px;
        --salty-card-shadow: inset 0 1px 0 rgba(255, 255, 255, 0.7), 0 2px 6px rgba(0, 0, 0, 0.2);
    }

    body { font-family: var(--salty-font-body) !important; }

    /* Solid Aqua-blue title instead of the modern gradient text (works on screen and in print) */
    #recipe-name {
        background: none !important;
        -webkit-background-clip: border-box !important;
        background-clip: border-box !important;
        -webkit-text-fill-color: currentColor !important;
        color: var(--salty-heading) !important;
    }

    h2 {
        color: var(--salty-heading) !important;
    }

    .recipe-directions-step-number {
        color: var(--salty-accent) !important;
        font-weight: 700 !important;
    }

    /* The Aqua theme is borderless — clear every border the base stylesheet draws (panels, photo
       frame, metadata pills). Panel backgrounds/shadows stay (handled below). Tag/category chips keep
       their solid border. */
    #recipe-info-container,
    #recipe-introduction-container,
    #recipe-ingredients-container,
    #recipe-directions-container,
    #recipe-notes-container,
    #recipe-variations-container,
    #recipe-meta-container,
    #recipe-image,
    #recipe-prep-time-list li,
    #recipe-yield-item,
    #recipe-servings-item {
        border: none !important;
    }

    /* Small metadata bubbles: no boxed look at all — no border, fill, or shadow (panels keep theirs). */
    #recipe-prep-time-list li,
    #recipe-yield-item,
    #recipe-servings-item {
        background: none !important;
        box-shadow: none !important;
    }

    /* Screen-only chrome: the desktop backdrop, glassy panels, shadows, and breathing room around the
       page. Kept out of print to avoid heavy ink and to leave the tuned print layout intact. */
    @media screen {
        body {
            background: linear-gradient(180deg, #eef2f7 0%, #d6dde6 100%) !important;
        }

        #recipe-name { text-shadow: 0 1px 0 rgba(255, 255, 255, 0.7); }

        /* Glassy "lozenge" panels (Categories + Tags share one, like the other sections) */
        #recipe-info-container,
        #recipe-introduction-container,
        #recipe-ingredients-container,
        #recipe-directions-container,
        #recipe-notes-container,
        #recipe-variations-container,
        #recipe-meta-container {
            background: linear-gradient(180deg, #ffffff 0%, #eef3f9 100%) !important;
            border-radius: var(--salty-card-radius) !important;
            box-shadow: var(--salty-card-shadow) !important;
        }
    }
    """
}
