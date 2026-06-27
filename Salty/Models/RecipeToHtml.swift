//
//  RecipeToHtml.swift
//  Salty
//
//  Created by Robert on 10/23/22.
//

import Foundation
import SwiftHtml
import ImageIO
import UniformTypeIdentifiers

extension Recipe {
    var asHtml: String {
        return asHtmlWithOptions(options: HTMLExportOptions())
    }

    // MARK: - Theming
    //
    // A recipe page is `<base CSS> + <theme CSS>`. The base (getDefaultCSS) defines the structure,
    // print layout, and default look via CSS variables declared in `:root`. A theme is just additional
    // CSS appended last, so it wins: override these variables and/or target the stable selectors below.
    // This is what a user-supplied theme file would slot into (see RecipeHtmlTheme).
    //
    // Theme variables (most colors/fonts route through these — overriding them restyles the whole page):
    //   --salty-font-body, --salty-font-heading
    //   --salty-page-bg, --salty-surface, --salty-panel-bg
    //   --salty-text, --salty-text-secondary, --salty-heading
    //   --salty-accent, --salty-link, --salty-link-hover, --salty-border
    //   --salty-star-filled, --salty-star-empty
    //   --salty-card-radius, --salty-card-shadow
    //
    // Stable selectors a theme can rely on:
    //   #recipe-name, #recipe-source, #recipe-sourceDetails, #recipe-image, #recipe-image-container
    //   #recipe-info-container, #recipe-introduction-container, #recipe-ingredients-container,
    //   #recipe-directions-container, #recipe-notes-container, #recipe-variations-container
    //   .recipe-content-area, .recipe-introduction
    //   .recipe-ingredients-list / .recipe-ingredient / .recipe-ingredient-heading
    //   .recipe-directions-list / .recipe-directions-step / .recipe-directions-step-number /
    //     .recipe-directions-step-text / .recipe-directions-heading
    //   .recipe-note-container / .recipe-note-heading / .recipe-note-text
    //   .recipe-variation-container / .recipe-variation-heading / .recipe-variation-text
    //   .recipe-rating-star-filled / .recipe-rating-star-empty
    // `course`/`categories`/`tags` are passed in because they live in separate tables, not on Recipe —
    // callers resolve them (see Recipe.libraryNames(database:)). Empty by default so callers without DB
    // access still work.
    func asHtmlWithOptions(options: HTMLExportOptions, theme: RecipeHtmlTheme = .modern,
                           course: String? = nil, categories: [String] = [], tags: [String] = []) -> String {
        let doc = Document(.html) {
            Html {
                Head {
                    Title(name)
                    Meta().charset("utf-8")
                    Meta().name("viewport").content("width=device-width, initial-scale=1.0")
                    Style(getDefaultCSS() + "\n\n" + theme.overrideCSS)
                }
                Body {
                    Main {
                        Section {
                            Div {
                                H1(name).id("recipe-name")
                                if !source.isEmpty { P(source).id("recipe-source") }
                                if !sourceDetails.isEmpty { P(sourceDetails).id("recipe-sourceDetails") }
                                
                                if let course = course, !course.isEmpty {
                                    P {
                                        Span("Course:").id("recipe-course-label")
                                        Span(course).id("recipe-course-text")
                                    }
                                    .id("recipe-course-container")
                                }

                                Div {
                                    if !yield.isEmpty {
                                        P(yield).id("recipe-yield-item")
                                    }
                                    if let servings = servings, servings > 0 {
                                        P("\(servings)").id("recipe-servings-item")
                                    }
                                }
                                .class("recipe-yield-and-servings-container")
                                
                                if options.includeRating && rating != .notSet {
                                    Div {
                                        Span("\(rating.rawValue)")
                                            .id("recipe-rating-raw-number")
                                        Span("/")
                                            .id("recipe-rating-raw-slash")
                                        Span("5")
                                            .id("recipe-rating-raw-max")
                                    }
                                    .id("recipe-rating-raw-container")
                                    Div {
                                        for _ in 1...Int(rating.rawValue) {
                                            Span("★")
                                                .class("recipe-rating-star-filled")
                                                .attribute("aria-hidden", "true")
                                        }
                                        for _ in Int(rating.rawValue)..<5 {
                                                Span("☆")
                                                    .class("recipe-rating-star-empty")
                                                    .attribute("aria-hidden", "true")
                                        }
                                    }
                                    .attribute("role", "img")
                                    .attribute("aria-label", "Rating: " + ((rating != .notSet) ? "\(rating.rawValue) of 5" : "none"))
                                    .id("recipe-rating-star-container")
                                }

                                if options.includeDifficulty && difficulty != .notSet {
                                    P {
                                        Span("Difficulty:")
                                            .id("recipe-difficulty-label")
                                        Span("\(difficulty.stringValue())")
                                            .id("recipe-difficulty-text")
                                    }
                                    .id("recipe-difficulty-container")
                                }
                                
                                if options.includePreparationTimes && preparationTimes.count > 0 {
                                    Section {
                                    H2("Preparation Time").id("recipe-prep-times-heading")
                                        Ul {
                                            for prepTime in preparationTimes {
                                                Li {
                                                    Span(prepTime.type).class("recipe-prep-time-type")
                                                    Span("").class("recipe-prep-time-separator")
                                                    Span(prepTime.timeString).class("recipe-prep-time-time")
                                                }
                                            }
                                        }.id("recipe-prep-time-list")
                                    }
                                    .id("recipe-prep-time-container")
                                }
                            }
                            .class("recipe-content-area")
                            
                            if options.includeImage, let imageAsBase64 = self.imageAsBase64 {
                                Section {
                                    Img(src: "data:image/jpeg;base64, \(imageAsBase64)", alt: "User-provided photograph of recipe")
                                        .id("recipe-image")
                                }
                                .id("recipe-image-container")
                            }
                        }
                        .id("recipe-info-container")
                        
                        if options.includeIntroduction && !introduction.isEmpty {
                            Section {
                                P(introduction)
                                    .class("recipe-introduction")
                            }
                            .id("recipe-introduction-container")
                        }

                        if options.includeIngredients {
                            Section {
                                H2("Ingredients").id("recipe-ingredients-heading")
                                    Ul {
                                        for ingredient in ingredients {
                                            if ingredient.isHeading {
                                                Li(ingredient.text)
                                                    .class("recipe-ingredient-heading")
                                            }
                                            else {
                                                Li(ingredient.text)
                                                    .class("recipe-ingredient")
                                            }
                                        }
                                    }
                                    .class("recipe-ingredients-list")
                            }
                            .id("recipe-ingredients-container")
                        }
                        
                        if options.includeDirections {
                            Section {
                                H2("Directions").id("recipe-directions-heading")
                                Ul {
                                    for (index, direction) in directions.enumerated() {
                                        if let isHeading = direction.isHeading, isHeading {
                                                Li(direction.text)
                                                    .class("recipe-directions-heading")
                                        }
                                        else {
                                            let stepNumber = directions.prefix(index + 1).filter { $0.isHeading != true }.count
                                            Li {
                                                Span("\(stepNumber).")
                                                    .class("recipe-directions-step-number")
                                                Span(direction.text)
                                                    .class("recipe-directions-step-text")
                                            }
                                            .class("recipe-directions-step")
                                        }
                                    }
                                }
                                .class("recipe-directions-list")
                            }
                            .id("recipe-directions-container")
                        }
                        
                        
                        if options.includeNotes && notes.count > 0 {
                            Section {
                                H2("Notes").id("recipe-notes")
                                for note in notes {
                                    Div {
                                        H3(note.title)
                                            .class("recipe-note-heading")
                                        P(note.content)
                                            .class("recipe-note-text")
                                    }
                                    .class("recipe-note-container")
                                }
                            }
                            .id("recipe-notes-container")
                        }
                        
                        if options.includeVariations && variations.count > 0 {
                            Section {
                                H2("Variations").id("recipe-variations-heading")
                                for variation in variations {
                                    Div {
                                        H3(variation.variationName)
                                            .class("recipe-variation-heading")
                                        P(variation.text)
                                            .class("recipe-variation-text")
                                    }
                                    .class("recipe-variation-container")
                                }
                            }
                            .id("recipe-variations-container")
                        }
                        
                        if !categories.isEmpty || !tags.isEmpty {
                            Section {
                                if !categories.isEmpty {
                                    H2("Categories").id("recipe-categories")
                                    Ul {
                                        for category in categories {
                                            Li(category).class("recipe-category")
                                        }
                                    }.id("categories-list")
                                }
                                if !tags.isEmpty {
                                    H2("Tags").id("recipe-tags")
                                    Ul {
                                        for tag in tags {
                                            Li(tag).class("recipe-tag")
                                        }
                                    }.id("tags-list")
                                }
                            }
                            .id("recipe-meta-container")
                        }

                    }
                }
            }
        }
        
        
        let html: String = DocumentRenderer(minify: false, indent: 2).render(doc)
        return html
    }

    var imageAsBase64: String? {
        // Modified from https://www.reddit.com/r/iOSProgramming/comments/10odrf5/convert_coregraphics_cgimage_and_base64_string
        guard let imageData = fullImageData else {
            return nil
        }
        guard let imageSource = CGImageSourceCreateWithData(imageData as CFData, nil) else {
            return nil
        }
        guard let cgImage = CGImageSourceCreateImageAtIndex(imageSource, 0, nil) else {
            return nil
        }
        // For compression, but unsure if need to manually "releae" CFDictionary, and default is easier for now (and may be perfectly fine)
        //let properties: [CFString : Any] = ([kCGImageDestinationLossyCompressionQuality: 0.8 as CFNumber] as CFDictionary) as! [CFString : Any]
        guard let mutableData = CFDataCreateMutable(nil, 0),
              //let dest = CGImageDestinationCreateWithData(mutableData, UTType.jpeg.identifier as CFString, 1, properties as CFDictionary)
              let dest = CGImageDestinationCreateWithData(mutableData, UTType.jpeg.identifier as CFString, 1, nil)
        else {
            return nil
        }
        CGImageDestinationAddImage(dest, cgImage, nil)
        guard CGImageDestinationFinalize(dest) else {
            return nil
        }
        let data = mutableData as Foundation.Data
        return data.base64EncodedString()
    }
}

func getDefaultCSS() -> String {
    return getCSSForHTML()
}

func getCSSForHTML() -> String {
let css =
"""
/*! normalize.css v8.0.1 | MIT License | github.com/necolas/normalize.css */

/* Document
========================================================================== */

/**
* 1. Correct the line height in all browsers.
* 2. Prevent adjustments of font size after orientation changes in iOS.
*/

html {
    line-height: 1.15;
    /* 1 */
    -webkit-text-size-adjust: 100%;
    /* 2 */
}

/* Sections
========================================================================== */

/**
* Remove the margin in all browsers.
*/

body {
    margin: 0;
}

/**
* Render the `main` element consistently in IE.
*/

main {
    display: block;
}

/**
* Correct the font size and margin on `h1` elements within `section` and
* `article` contexts in Chrome, Firefox, and Safari.
*/

h1 {
    font-size: 2em;
    margin: 0.67em 0;
}

/* Grouping content
========================================================================== */

/**
* 1. Add the correct box sizing in Firefox.
* 2. Show the overflow in Edge and IE.
*/

hr {
    box-sizing: content-box;
    /* 1 */
    height: 0;
    /* 1 */
    overflow: visible;
    /* 2 */
}

/**
* 1. Correct the inheritance and scaling of font size in all browsers.
* 2. Correct the odd `em` font sizing in all browsers.
*/

pre {
    font-family: monospace, monospace;
    /* 1 */
    font-size: 1em;
    /* 2 */
}

/* Text-level semantics
========================================================================== */

/**
* Remove the gray background on active links in IE 10.
*/

a {
    background-color: transparent;
}

/**
* 1. Remove the bottom border in Chrome 57-
* 2. Add the correct text decoration in Chrome, Edge, IE, Opera, and Safari.
*/

abbr[title] {
    border-bottom: none;
    /* 1 */
    text-decoration: underline;
    /* 2 */
    text-decoration: underline dotted;
    /* 2 */
}

/**
* Add the correct font weight in Chrome, Edge, and Safari.
*/

b,
strong {
    font-weight: bolder;
}

/**
* 1. Correct the inheritance and scaling of font size in all browsers.
* 2. Correct the odd `em` font sizing in all browsers.
*/

code,
kbd,
samp {
    font-family: monospace, monospace;
    /* 1 */
    font-size: 1em;
    /* 2 */
}

/**
* Add the correct font size in all browsers.
*/

small {
    font-size: 80%;
}

/**
* Prevent `sub` and `sup` elements from affecting the line height in
* all browsers.
*/

sub,
sup {
    font-size: 75%;
    line-height: 0;
    position: relative;
    vertical-align: baseline;
}

sub {
    bottom: -0.25em;
}

sup {
    top: -0.5em;
}

/* Embedded content
========================================================================== */

/**
* Remove the border on images inside links in IE 10.
*/

img {
    border-style: none;
}

/* Forms
========================================================================== */

/**
* 1. Change the font styles in all browsers.
* 2. Remove the margin in Firefox and Safari.
*/

button,
input,
optgroup,
select,
textarea {
    font-family: inherit;
    /* 1 */
    font-size: 100%;
    /* 1 */
    line-height: 1.15;
    /* 1 */
    margin: 0;
    /* 2 */
}

/**
* Show the overflow in IE.
* 1. Show the overflow in Edge.
*/

button,
input {
    /* 1 */
    overflow: visible;
}

/**
* Remove the inheritance of text transform in Edge, Firefox, and IE.
* 1. Remove the inheritance of text transform in Firefox.
*/

button,
select {
    /* 1 */
    text-transform: none;
}

/**
* Correct the inability to style clickable types in iOS and Safari.
*/

button,
[type="button"],
[type="reset"],
[type="submit"] {
    -webkit-appearance: button;
}

/**
* Remove the inner border and padding in Firefox.
*/

button::-moz-focus-inner,
[type="button"]::-moz-focus-inner,
[type="reset"]::-moz-focus-inner,
[type="submit"]::-moz-focus-inner {
    border-style: none;
    padding: 0;
}

/**
* Restore the focus styles unset by the previous rule.
*/

button:-moz-focusring,
[type="button"]:-moz-focusring,
[type="reset"]:-moz-focusring,
[type="submit"]:-moz-focusring {
    outline: 1px dotted ButtonText;
}

/**
* Correct the padding in Firefox.
*/

fieldset {
    padding: 0.35em 0.75em 0.625em;
}

/**
* 1. Correct the text wrapping in Edge and IE.
* 2. Correct the color inheritance from `fieldset` elements in IE.
* 3. Remove the padding so developers are not caught out when they zero out
*    `fieldset` elements in all browsers.
*/

legend {
    box-sizing: border-box;
    /* 1 */
    color: inherit;
    /* 2 */
    display: table;
    /* 1 */
    max-width: 100%;
    /* 1 */
    padding: 0;
    /* 3 */
    white-space: normal;
    /* 1 */
}

/**
* Add the correct vertical alignment in Chrome, Firefox, and Opera.
*/

progress {
    vertical-align: baseline;
}

/**
* Remove the default vertical scrollbar in IE 10+.
*/

textarea {
    overflow: auto;
}

/**
* 1. Add the correct box sizing in IE 10.
* 2. Remove the padding in IE 10.
*/

[type="checkbox"],
[type="radio"] {
    box-sizing: border-box;
    /* 1 */
    padding: 0;
    /* 2 */
}

/**
* Correct the cursor style of increment and decrement buttons in Chrome.
*/

[type="number"]::-webkit-inner-spin-button,
[type="number"]::-webkit-outer-spin-button {
    height: auto;
}

/**
* 1. Correct the odd appearance in Chrome and Safari.
* 2. Correct the outline style in Safari.
*/

[type="search"] {
    -webkit-appearance: textfield;
    /* 1 */
    outline-offset: -2px;
    /* 2 */
}

/**
* Remove the inner padding in Chrome and Safari on macOS.
*/

[type="search"]::-webkit-search-decoration {
    -webkit-appearance: none;
}

/**
* 1. Correct the inability to style clickable types in iOS and Safari.
* 2. Change font properties to `inherit` in Safari.
*/

::-webkit-file-upload-button {
    -webkit-appearance: button;
    /* 1 */
    font: inherit;
    /* 2 */
}

/* Interactive
========================================================================== */

/*
* Add the correct display in Edge, IE 10+, and Firefox.
*/

details {
    display: block;
}

/*
* Add the correct display in all browsers.
*/

summary {
    display: list-item;
}

/* Misc
========================================================================== */

/**
* Add the correct display in IE 10+.
*/

template {
    display: none;
}

/**
* Add the correct display in IE 10.
*/

[hidden] {
    display: none;
}

/****** Elad Shechter's RESET *******/
/*** box sizing border-box for all elements ***/
*,
*::before,
*::after {
    box-sizing: border-box;
}

a {
    text-decoration: none;
    color: inherit;
    cursor: pointer;
}

button {
    background-color: transparent;
    color: inherit;
    border-width: 0;
    padding: 0;
    cursor: pointer;
}

figure {
    margin: 0;
}

input::-moz-focus-inner {
    border: 0;
    padding: 0;
    margin: 0;
}

ul,
ol,
dd {
    margin: 0;
    padding: 0;
    list-style: none;
}

h1,
h2,
h3,
h4,
h5,
h6 {
    margin: 0;
    font-size: inherit;
    font-weight: inherit;
}

p {
    margin: 0;
}

cite {
    font-style: normal;
}

fieldset {
    border-width: 0;
    padding: 0;
    margin: 0;
}

/*** typography.css ***/
html {
    font-size: 1px;
    /*for using REM units*/
}

/** CUSTOM **/

/* ===========================================================================
   THEME TOKENS — a theme restyles recipes by overriding these variables (and/or
   adding rules); the HTML structure, ids, and class names below stay constant.
   See RecipeHtmlTheme.swift and the "Theming" doc comment in asHtmlWithOptions.
   =========================================================================== */
:root {
    --salty-font-body: -apple-system, BlinkMacSystemFont, 'Segoe UI', 'Roboto', 'Oxygen', 'Ubuntu', 'Fira Sans', 'Droid Sans', 'Helvetica Neue', sans-serif;
    --salty-font-heading: var(--salty-font-body);
    --salty-page-bg: #ffffff;
    --salty-surface: #ffffff;
    --salty-panel-bg: #f8f9fa;
    --salty-text: rgb(25, 25, 25);
    --salty-text-secondary: #5a5a5e;
    --salty-heading: #1d1d1f;
    --salty-accent: #0a84ff;
    --salty-link: blue;
    --salty-link-hover: cornflowerblue;
    --salty-border: #e1e5e9;
    --salty-star-filled: #ffd60a;
    --salty-star-empty: #d1d5db;
    --salty-card-radius: 16px;
    --salty-card-shadow: 0 8px 32px rgba(0, 0, 0, 0.12);
}

body {
    font-family: var(--salty-font-body);
    font-size: 14rem;
    font-weight: 400;
    line-height: 1.2;
    padding: 2rem;
    background: var(--salty-page-bg);
    color: var(--salty-text);
    max-width: 1200px;
    margin: 0 auto;
    padding-left: 8rem;
    padding-right: 8rem;
}

a:link,
a:visited {
    color: var(--salty-link);
}

a:hover {
    color: var(--salty-link-hover);
}

/* Recipe Layout */
main {
    display: grid;
    grid-template-columns: 1fr;
    gap: 2rem;
    padding: 1rem;
}

@media (min-width: 750px) {
    main {
        grid-template-columns: 35% 65%;
        gap: 5rem;
    }

    #recipe-info-container {
        grid-column: 1 / -1;
    }

    #recipe-ingredients-container {
        grid-column: 1;
    }

    #recipe-directions-container {
        grid-column: 2;
    }

    #recipe-notes-container {
        grid-column: 1 / -1;
    }
}

/* Recipe Info Section */
#recipe-info-container {
   font-size: 90%;
   margin-bottom: 2rem;
   position: relative;
   display: grid;
   grid-template-columns: 1fr auto;
   gap: 2rem;
   align-items: start;
}

/* Recipe Image Styling */
#recipe-image-container {
   grid-column: 2;
   grid-row: 1;
   margin-top: 0;
   align-self: start;
}

#recipe-image {
   width: 150px;
   height: 150px;
   max-width: 400px;
   max-height: 400px;
   object-fit: cover;
   border-radius: var(--salty-card-radius);
   box-shadow: var(--salty-card-shadow);
   border: 1px solid var(--salty-border);
   transition: transform 0.2s ease;
}

#recipe-image:hover {
   transform: scale(1.02);
}

/* Recipe Content Area */
.recipe-content-area {
   grid-column: 1;
}

/* Responsive adjustments for image */
@media (max-width: 768px) {
   #recipe-info-container {
       grid-template-columns: 1fr;
       gap: 1rem;
   }
   
   #recipe-image-container {
       grid-column: 1;
       grid-row: auto;
       text-align: center;
       margin-top: 0;
   }
   
   #recipe-image {
       width: 100%;
       max-width: 200px;
       height: auto;
       max-height: 200px;
   }
}

#recipe-name {
    font-size: 200%;
    font-weight: bold;
    margin: 0.75em 0;
    word-wrap: break-word;
    overflow-wrap: break-word;
    hyphens: auto;
}

#recipe-source,
#recipe-sourceDetails {
    margin: 0.5em 0;
    word-wrap: break-word;
    overflow-wrap: break-word;
}

/* Ingredients Section */
.recipe-ingredients-container {
    list-style: none;
    padding: 0;
    margin: 0;
}

.recipe-ingredients-list {
    margin-top: 0.5rem;
}

.recipe-ingredient-heading {
    font-weight: bold;
    margin-top: 1em;
    margin-bottom: 0.5em;
    color: rgb(75, 75, 75);
}

.recipe-ingredient {
    margin: 0.25em 0;
    padding-left: 1em;
}

/* Directions Section */
.recipe-directions-list {
    list-style: none;
    padding: 0;
    margin: 0;
}

.recipe-directions-step,
.recipe-directions-step-with-name {
    margin: 1em 0;
    padding-left: 1em;
    position: relative;
}

.recipe-directions-step-with-name {
    display: flex;
    flex-direction: column;
    gap: 0.25em;
}



/* Typography */
h1,
h2,
h3,
h4,
h5,
h6 {
    margin: 0;
    line-height: 1.2;
}

h1 {
    font-size: 200%;
}

h2 {
    font-size: 133%;
}

h3 {
    font-size: 105%;
}

h4 {
    font-size: 95%;
}

h5,
h6 {
    font-size: 90%;
}

/* Lists and Definition Lists */
dl {
    padding: 0;
    margin: 0.5rem 0;
}

dt {
    font-weight: bold;
    display: inline;
    float: left;
    clear: left;
    padding-right: 0.5em;
}

dt::after {
    content: ":";
}

dd {
    display: block;
    margin: 0 0 0.5rem 0.9rem;
}

/* Star Rating Styling */
#recipe-rating-star-container {
    display: block;
    align-items: center;
    gap: 0.15em;
    margin: 0.75em 0;
    /* padding: 0.5em 0.75em;
background: linear-gradient(135deg, var(--salty-panel-bg) 0%, var(--salty-surface) 100%); */
    /* border-radius: 12px;
border: 1px solid var(--salty-border);
box-shadow: 0 2px 8px rgba(0, 0, 0, 0.04); */
}

.recipe-rating-star-filled {
    color: var(--salty-star-filled);
    font-size: 1.3em;
    text-shadow: 0 1px 2px rgba(255, 214, 10, 0.3);
}

.recipe-rating-star-empty {
    color: var(--salty-star-empty);
    font-size: 1.3em;
}

/* Rating Raw Numbers - Hidden when stars are present */
#recipe-rating-raw-container {
    display: none;
}

/* Difficulty Display */
#recipe-difficulty-container {
    margin: 0.75em 0;
    /* padding: 0.5em 0.5em; */
    /* background: linear-gradient(135deg, var(--salty-panel-bg) 0%, var(--salty-surface) 100%);
border-radius: 12px;
border: 1px solid var(--salty-border);
box-shadow: 0 2px 8px rgba(0, 0, 0, 0.04); */
    display: block;
}

#recipe-difficulty-label {
    font-weight: 600;
    color: var(--salty-text-secondary);
    margin-right: 0.5em;
}

#recipe-difficulty-text {
    font-weight: 500;
    color: var(--salty-heading);
    text-transform: capitalize;
}

#recipe-course-container {
    margin: 0.75em 0;
    display: block;
}

#recipe-course-label {
    font-weight: 600;
    color: var(--salty-text-secondary);
    margin-right: 0.5em;
}

#recipe-course-text {
    font-weight: 500;
    color: var(--salty-heading);
}

/* Recipe Header Styling */
#recipe-name {
    font-size: 2.5em;
    font-weight: 700;
    margin: 0.5em 0;
    background: linear-gradient(135deg, var(--salty-heading) 0%, #424245 100%);
    -webkit-background-clip: text;
    -webkit-text-fill-color: transparent;
    background-clip: text;
    letter-spacing: -0.02em;
    line-height: 1.1;
}

#recipe-source,
#recipe-sourceDetails {
    margin: 0.5em 0;
    color: var(--salty-text-secondary);
    font-size: 0.95em;
    font-weight: 400;
}

/* Preparation Time Styling - Capsule Design */
#recipe-prep-times-heading {
    font-size: 1.4em;
    font-weight: 600;
    color: var(--salty-heading);
    margin: 1.5em 0 0.75em 0;
}

#recipe-prep-time-list {
    display: flex;
    flex-wrap: wrap;
    gap: 0.75em;
    margin: 0.5em 0;
    list-style: none;
    padding: 0;
}

#recipe-prep-time-list li {
    background: linear-gradient(135deg, var(--salty-panel-bg) 0%, var(--salty-surface) 100%);
    border: 1px solid var(--salty-border);
    border-radius: 20px;
    padding: 0.75em;
    box-shadow: 0 2px 8px rgba(0, 0, 0, 0.04);
    min-width: 70px;
    text-align: center;
    display: flex;
    flex-direction: column;
    gap: 0.25em;
}

.recipe-prep-time-type {
    font-weight: 600;
    color: var(--salty-text-secondary);
    font-size: 0.9em;
}

.recipe-prep-time-separator {
    display: none;
}

.recipe-prep-time-time {
    color: var(--salty-heading);
    font-weight: 600;
    font-size: 1.1em;
}

/* Section Headers */
h2 {
    font-size: 1.6em;
    font-weight: 600;
    color: var(--salty-heading);
    margin: 0.5rem 0 0.5rem 0;
}

/* Ingredients Styling */
.recipe-ingredient-heading {
    font-weight: 600;
    margin: 0.5em 0 0.25em 0;
    color: var(--salty-heading);
    font-size: 0.95em;
}

.recipe-ingredient {
    margin: 0;
    padding: 0.25em 0 0.25em 1em;
    position: relative;
}

.recipe-ingredient::before {
    content: '•';
    position: absolute;
    left: 0;
}

/* Directions Styling */
.recipe-directions-step {
    margin: 1em 0;
    padding: 0.5em 0;
    line-height: 1.6;
    display: flex;
    gap: 0.5em;
}

.recipe-directions-step-number {
    font-weight: bold;
    color: var(--salty-heading);
    flex-shrink: 0;
}

.recipe-directions-step-text {
    flex: 1;
}

.recipe-directions-list {
    list-style: none;
    padding: 0;
    margin: 0;
}

.recipe-directions-heading {
    margin: 0.5em 0 0.25em 0;
    padding: 0.25em 0;
    color: var(--salty-heading);
    font-weight: 600;
    font-size: 0.95em;
    position: relative;
}

/* Introduction Styling */
#recipe-introduction-container {
    font-size: 90%;
    margin-bottom: 2rem;
    font-style: italic;
}

.recipe-introduction {
    margin: 0;
    line-height: 1.6;
    color: var(--salty-heading);
}

/* Metadata Styling */
.recipe-yield-and-servings-container {
    display: flex;
    flex-wrap: wrap;
    gap: 0.5em;
    margin: 0;
}

#recipe-yield-item, #recipe-servings-item {
    padding: 0.25em 0.75em 0.25em 0;
    background: rgba(255, 255, 255, 0.66);
    border-radius: 20px;
    font-size: 0.9em;
    font-weight: 500;
}

#recipe-yield-item::before {
    content: "Yield: ";
    font-weight: normal;
}

#recipe-servings-item::before {
    content: "Servings: ";
    font-weight: normal;
}

/* Notes Styling */
.recipe-note-heading {
    font-size: 0.95em;
    font-weight: 600;
    color: var(--salty-heading);
}

.recipe-note-container {
    margin: 1em 0;
    padding: 0.5em 1.5em;
    background: var(--salty-panel-bg);
    border-radius: 12px;
    line-height: 1.25;
    color: var(--salty-heading);
}

#recipe-notes-container {
    font-size: 90%;
    margin-top: 2rem;
}

/* Variations Styling */
.recipe-variation-heading {
    font-size: 0.95em;
    font-weight: 600;
    color: var(--salty-heading);
}

.recipe-variation-container {
    margin: 1em 0;
    padding: 0.5em 1.5em;
    background: var(--salty-panel-bg);
    border-radius: 12px;
    line-height: 1.25;
    color: var(--salty-heading);
}

#recipe-variations-container {
    font-size: 90%;
    margin-top: 2rem;
}


/* Tags Styling */
.recipe-tag {
    display: inline-block;
    padding: 0.5em 1em;
    margin: 0.25em;
    border: 1px solid var(--salty-border);
    border-radius: 20px;
    font-size: 0.9em;
    font-weight: 500;
}

#tags-list {
    display: flex;
    flex-wrap: wrap;
    gap: 0.5em;
    margin: 1em 0;
}

/* Categories Styling — same capsule as tags, just a slightly smaller font. */
.recipe-category {
    display: inline-block;
    padding: 0.5em 1em;
    margin: 0.25em;
    border: 1px solid var(--salty-border);
    border-radius: 20px;
    font-size: 0.8em;
    font-weight: 500;
}

#categories-list {
    display: flex;
    flex-wrap: wrap;
    gap: 0.5em;
    margin: 1em 0;
}

/* Container Styling */
/* #recipe-meta-container holds Categories + Tags together in one card, like the other sections. */
#recipe-info-container,
#recipe-introduction-container,
#recipe-ingredients-container,
#recipe-directions-container,
#recipe-notes-container,
#recipe-variations-container,
#recipe-meta-container {
    background: white;
    border-radius: 20px;
    padding: 1.5em 2em;
    margin: 1em 1rem;
    box-shadow: 0 8px 32px rgba(0, 0, 0, 0.08);
    border: 1px solid #f2f2f2;
    transition: all 0.3s ease;
}

/* Removed hover effects for static design */

/* Main Layout Improvements */
main {
    background: white;
    min-height: 100vh;
    padding: 2rem;
}

body {
    background: white;
    font-family: -apple-system, BlinkMacSystemFont, 'SF Pro Display', 'Segoe UI', 'Roboto', sans-serif;
    font-size: 14rem;
    font-weight: 400;
    line-height: 1.6;
    color: var(--salty-heading);
    max-width: 1200px;
    margin: 0 auto;
}

/* Responsive Design */
@media (max-width: 768px) {
    #recipe-name {
        font-size: 2em;
    }

    #recipe-info-container,
    #recipe-introduction-container,
    #recipe-ingredients-container,
    #recipe-directions-container,
    #recipe-notes-container,
    #recipe-variations-container,
    #recipe-meta-container {
        padding: 1.5em;
        margin: 0.5em 0;
    }
}

/* Print-specific styles */
/* Page size + margins are owned here (NOT by body padding and NOT by the print dialog's margins,
   which the app sets to 0) so they don't stack and clip content. */
@page {
    size: letter;
    margin: 0.5in;
}

@media print {
    /* Global font size reduction to 90% */
    html {
        font-size: 0.9rem !important;
    }

    body {
        font-size: 90% !important;
        line-height: 1.4 !important; /* Reduce line height for tighter spacing */
        margin: 0 !important;
        padding: 0 !important; /* margins come from @page; avoids double margins / right-edge clipping */
    }

    /* Safety: nothing prints wider than the page; images never split across a page. */
    img {
        max-width: 100% !important;
        break-inside: avoid !important;
        page-break-inside: avoid !important;
    }
    
    /* Reduce spacing for all text elements */
    p, li, div, span {
        line-height: 1.4 !important;
    }
    
    /* Reduce margins and padding throughout */
    main {
        grid-template-columns: 1fr !important;
        gap: 0.5rem !important; /* Reduced from 1rem */
        padding: 0;
    }
    
    /* Prevent lines of text from being cut in half - avoid breaking inside text elements */
    p, span, .recipe-introduction, .recipe-directions-step-text, .recipe-note-text, .recipe-variation-text {
        break-inside: avoid !important;
        page-break-inside: avoid !important;
        orphans: 2 !important; /* Keep at least 2 lines together */
        widows: 2 !important; /* Keep at least 2 lines together */
    }
    
    /* Allow page breaks inside all containers - but prevent breaking text lines */
    #recipe-info-container,
    #recipe-introduction-container,
    #recipe-ingredients-container,
    #recipe-directions-container,
    #recipe-notes-container,
    #recipe-variations-container,
    #recipe-meta-container {
        break-inside: auto !important;
        page-break-inside: auto !important;
        border: none !important;
        box-shadow: none !important;
        /* Reduce padding/margin */
        padding: 0.5em 1em !important;
        margin: 0.5em 0 !important;
    }
    
    /* Keep section headers with the content that follows (no orphaned heading at a page bottom). */
    #recipe-ingredients-container h2,
    #recipe-directions-container h2,
    #recipe-notes-container h2,
    #recipe-variations-container h2 {
        break-after: avoid !important;
        page-break-after: avoid !important;
        break-inside: avoid !important; /* Don't break headers themselves */
        page-break-inside: avoid !important;
        margin-top: 0.5em !important; /* Reduce top margin */
        margin-bottom: 0.25em !important; /* Reduce bottom margin */
    }
    
    /* Make Ingredients and Directions headings larger */
    #recipe-ingredients-container h2,
    #recipe-directions-container h2 {
        font-size: 1.1em !important; /* Larger than other h2 elements */
        font-weight: 700 !important; /* Bolder */
    }
    
    /* Allow lists to break across pages, but keep list items intact */
    .recipe-ingredients-list,
    .recipe-directions-list {
        break-inside: auto !important;
        page-break-inside: auto !important;
        margin: 0.25em 0 !important; /* Reduce list margins */
        padding: 0 !important;
    }
    
    /* Prevent breaking individual list items (ingredients/directions) */
    .recipe-directions-list li {
        break-inside: avoid !important;
        page-break-inside: avoid !important;
        margin: 0.15em 0 !important; /* Reduce spacing between list items */
        padding: 0.1em 0 !important;
    }
    
    /* Fix ingredient bullets - ensure they appear to the left of text */
    .recipe-ingredients-list li {
        break-inside: avoid !important;
        page-break-inside: avoid !important;
        margin: 0.15em 0 !important;
        padding: 0.1em 0 0.1em 1.2em !important; /* Ensure enough padding for bullet */
        position: relative !important;
    }
    
    .recipe-ingredient {
        padding-left: 1.2em !important; /* Ensure enough space for bullet */
    }
    
    .recipe-ingredient::before {
        content: '•' !important;
        position: absolute !important;
        left: 0.2em !important; /* Position bullet slightly to the right of left edge */
    }
    
    /* Prevent breaking individual direction steps. WebKit's print engine doesn't honor
       break-inside:avoid on flex containers, which sliced a wrapped line across pages — so for print
       lay steps out as normal block text (number + text inline) where avoid works reliably. */
    .recipe-directions-step,
    .recipe-directions-step-with-name {
        display: block !important;
        break-inside: avoid !important;
        page-break-inside: avoid !important;
        margin: 0.5em 0 !important; /* Reduce spacing between steps */
    }

    .recipe-directions-step-number {
        display: inline !important;
        margin-right: 0.4em !important;
    }

    .recipe-directions-step-text {
        display: inline !important;
    }
    
    /* Prevent breaking individual notes and variations */
    .recipe-note-container,
    .recipe-variation-container {
        break-inside: avoid !important;
        page-break-inside: avoid !important;
        margin: 0.75em 0 !important; /* Reduce spacing */
        padding: 0.5em 1em !important; /* Reduce padding */
    }
    
    /* Reduce spacing for ingredient headings */
    .recipe-ingredient-heading,
    .recipe-directions-heading {
        margin-top: 0.5em !important;
        margin-bottom: 0.25em !important;
    }
    
    /* Reduce spacing for introduction */
    .recipe-introduction {
        margin: 0.5em 0 !important;
    }
    
    /* Allow page breaks between major sections */
    #recipe-info-container,
    #recipe-introduction-container {
        break-after: auto;
        page-break-after: auto;
    }
    
    #recipe-ingredients-container,
    #recipe-directions-container {
        grid-column: 1 !important;
    }
    
    body,
    main {
        background: white !important;
    }
    
    /* Reduce font sizes to 90% for all headings */
    h1, h2, h3, h4, h5, h6 {
        font-size: 90% !important;
    }
    
    /* Make direction step text and ingredient text smaller */
    .recipe-directions-step-text,
    .recipe-ingredient {
        font-size: 0.9em !important; /* Smaller than body text */
    }
    
    #recipe-name {
        font-size: 1.8em !important; /* 90% of 2em */
        /* Flatten the modern gradient-text for print; honor the theme's heading color. */
        background: none !important;
        -webkit-background-clip: unset !important;
        -webkit-text-fill-color: unset !important;
        background-clip: unset !important;
        color: var(--salty-heading) !important;
        margin: 0.5em 0 !important; /* Reduce margins */
    }

    /* Reduce spacing for source info; honor the theme's secondary text color. */
    #recipe-source,
    #recipe-sourceDetails {
        margin: 0.25em 0 !important;
        color: var(--salty-text-secondary) !important;
    }
    
    /* Lay the header out as a row so the photo sits top-right of the name/source instead of taking
       its own full-width row below them (saves vertical space). The image markup already follows the
       text block in the DOM, so a flex row puts it on the right automatically. */
    #recipe-info-container {
        display: flex !important;
        flex-direction: row !important;
        align-items: flex-start !important;
        gap: 0.5em 1em !important;
        break-inside: avoid !important;
        page-break-inside: avoid !important;
    }

    #recipe-info-container .recipe-content-area {
        flex: 1 1 auto !important;
        min-width: 0 !important; /* allow the text column to shrink next to the image */
    }

    #recipe-image-container {
        flex: 0 0 auto !important;
        margin: 0 !important;
        padding: 0 !important;
    }

    /* Smaller photo for the top-right corner. */
    #recipe-image {
        max-width: 2in !important;
        max-height: 2in !important;
        width: auto;
        height: auto;
        object-fit: contain;
    }
}
"""
 return css
}
