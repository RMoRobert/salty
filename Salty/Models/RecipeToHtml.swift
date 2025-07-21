//
//  RecipeToHtml.swift
//  Salty
//
//  Created by Robert on 10/23/22.
//

import Foundation
import SwiftHtml

extension Recipe {
    var asHtml: String {
        let doc = Document(.html) {
            Html {
                Head {
                    Title(name)
                    Meta().charset("utf-8")
                    //let cssPath = Bundle.main.path(forResource: "recipe-default", ofType: "css") ?? ""
                    //Link(rel: .stylesheet).href(cssPath)
                    Style(getDefaultCSS())
                }
                Body {
                    Main {
                        Section {
                            Div {
                                H1(name).id("recipe-name")
                                //if author != "" { P(author).id("recipe-author") }
                                if source  != ""{ P(source).id("recipe-source") }
                                if sourceDetails != "" { P(sourceDetails).id("recipe-sourceDetails") }
                                
                                if rating != .notSet {
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

                                if difficulty != .notSet {
                                    P {
                                        Span("Difficulty:")
                                            .id("recipe-difficulty-label")
                                        Span("\(difficulty.stringValue())")
                                            .id("recipe-difficulty-text")
                                    }
                                    .id("recipe-difficulty-container")
                                }
                                
                                if preparationTimes.count > 0 {
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
                            
                            if let imageFilename = self.imageFilename {
                                Section {
                                    Img(src: FileManager.saltyImageFolderUrl.absoluteString + imageFilename, alt: "User-provided photograph of recipe")
                                        .id("recipe-image")
                                }
                                .id("recipe-image-container")
                            }
                        }
                        .id("recipe-info-container")

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
                        
                        Section {
                            H2("Directions").id("recipe-directions-heading")
                            Ul {
                                for direction in directions {
                                    if let isHeading = direction.isHeading, isHeading {
                                            Li(direction.text)
                                                .class("recipe-directions-heading")
                                    }
                                    else {
                                        Li(direction.text)
                                            .class("recipe-directions-step")
                                    }
                                }
                            }
                            .class("recipe-directions-list")
                        }
                        .id("recipe-directions-container")
                        
                        
                        Section {
                            if notes.count > 0 {
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
                        }
                        .id("recipe-notes-container")
                        
                        
                        if tags.count > 0 {
                            Section {
                                H2("Tags").id("recipe-tags")
                                Ul {
                                    for tag in tags {
                                        Li(tag).class("recipe-tag")
                                    }
                                }.id(("tags-list"))
                            }
                            .id("recipe-tags-container")
                        }
                        
                    }
                }
            }
        }
        
        let html: String = DocumentRenderer(minify: false, indent: 2).render(doc)
        return html
    }
}

func getDefaultCSS() -> String {
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

body {
    font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', 'Roboto', 'Oxygen', 'Ubuntu', 'Fira Sans', 'Droid Sans', 'Helvetica Neue', sans-serif;
    font-size: 14rem;
    font-weight: 400;
    line-height: 1.2;
    color: #222;
    padding: 2rem;
    background-color: white;
    color: rgb(25, 25, 25);
    max-width: 1200px;
    margin: 0 auto;
    padding-left: 8rem;
    padding-right: 8rem;
}

a:link,
a:visited {
    color: blue;
}

a:hover {
    color: cornflowerblue;
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
   grid-row: 1 / span 3;
   margin-top: 1rem;
}

#recipe-image {
   width: 200px;
   height: 200px;
   object-fit: cover;
   border-radius: 16px;
   box-shadow: 0 8px 32px rgba(0, 0, 0, 0.12);
   border: 1px solid #e1e5e9;
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
       max-width: 300px;
       height: auto;
       max-height: 300px;
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
background: linear-gradient(135deg, #f8f9fa 0%, #ffffff 100%); */
    /* border-radius: 12px;
border: 1px solid #e1e5e9;
box-shadow: 0 2px 8px rgba(0, 0, 0, 0.04); */
}

.recipe-rating-star-filled {
    color: #ffd60a;
    font-size: 1.3em;
    text-shadow: 0 1px 2px rgba(255, 214, 10, 0.3);
}

.recipe-rating-star-empty {
    color: #d1d5db;
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
    /* background: linear-gradient(135deg, #f8f9fa 0%, #ffffff 100%);
border-radius: 12px;
border: 1px solid #e1e5e9;
box-shadow: 0 2px 8px rgba(0, 0, 0, 0.04); */
    display: block;
}

#recipe-difficulty-label {
    font-weight: 600;
    color: #86868b;
    margin-right: 0.5em;
}

#recipe-difficulty-text {
    font-weight: 500;
    color: #1d1d1f;
    text-transform: capitalize;
}

/* Recipe Header Styling */
#recipe-name {
    font-size: 2.5em;
    font-weight: 700;
    margin: 0.5em 0;
    background: linear-gradient(135deg, #1d1d1f 0%, #424245 100%);
    -webkit-background-clip: text;
    -webkit-text-fill-color: transparent;
    background-clip: text;
    letter-spacing: -0.02em;
    line-height: 1.1;
}

#recipe-source,
#recipe-sourceDetails {
    margin: 0.5em 0;
    color: #86868b;
    font-size: 0.95em;
    font-weight: 400;
}

/* Preparation Time Styling - Capsule Design */
#recipe-prep-times-heading {
    font-size: 1.4em;
    font-weight: 600;
    color: #1d1d1f;
    margin: 1.5em 0 0.75em 0;
}

#recipe-prep-time-list {
    display: flex;
    flex-wrap: wrap;
    gap: 0.75em;
    margin: 1em 0;
    list-style: none;
    padding: 0;
}

#recipe-prep-time-list li {
    background: linear-gradient(135deg, #f8f9fa 0%, #ffffff 100%);
    border: 1px solid #e1e5e9;
    border-radius: 20px;
    padding: 1em;
    box-shadow: 0 2px 8px rgba(0, 0, 0, 0.04);
    min-width: 80px;
    text-align: center;
    display: flex;
    flex-direction: column;
    gap: 0.25em;
}

.recipe-prep-time-type {
    font-weight: 600;
    color: #86868b;
    font-size: 0.9em;
}

.recipe-prep-time-separator {
    display: none;
}

.recipe-prep-time-time {
    color: #1d1d1f;
    font-weight: 600;
    font-size: 1.1em;
}

/* Section Headers */
h2 {
    font-size: 1.6em;
    font-weight: 600;
    color: #1d1d1f;
    margin: 0.5rem 0 0.5rem 0;
}

/* Ingredients Styling */
.recipe-ingredient-heading {
    font-weight: 600;
    margin: 0.5em 0 0.25em 0;
    color: #1f1f1f;
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
    padding: 1em 1.5em;
    background: linear-gradient(135deg, #f8f9fa 0%, #ffffff 100%);
    border-radius: 16px;
    border: 1px solid #e1e5e9;
    box-shadow: 0 2px 8px rgba(0, 0, 0, 0.04);
    transition: all 0.2s ease;
    position: relative;
    line-height: 1.6;
}

.recipe-directions-step::before {
    content: counter(step-counter);
    counter-increment: step-counter;
    position: absolute;
    left: -1em;
    top: 1em;
    background: linear-gradient(135deg, #007aff 0%, #5856d6 100%);
    color: white;
    width: 2em;
    height: 2em;
    border-radius: 50%;
    display: flex;
    align-items: center;
    justify-content: center;
    font-weight: 600;
    font-size: 0.9em;
    box-shadow: 0 2px 8px rgba(0, 122, 255, 0.3);
}

.recipe-directions-list {
    counter-reset: step-counter;
    list-style: none;
    padding: 0;
    margin: 0;
}

.recipe-directions-heading {
    margin: 0.5em 0 0.25em 0;
    padding: 0.25em 0;
    color: #1f1f1f;
    font-weight: 600;
    font-size: 0.95em;
    position: relative;
}

/* Notes Styling */
.recipe-note-heading {
    font-size: 0.95em;
    font-weight: 600;
    color: #1f1f1f;
}

.recipe-note-container {
    margin: 1em 0;
    padding: 0.5em 1.5em;
    background: #f8f9fa;
    border-radius: 12px;
    line-height: 1.25;
    color: #1d1d1f;
}

#recipe-notes-container {
    font-size: 90%;
    margin-top: 2rem;
}


/* Tags Styling */
.recipe-tag {
    display: inline-block;
    /* background: linear-gradient(135deg, #007aff 0%, #5856d6 100%);
    color: white; */
    padding: 0.5em 1em;
    margin: 0.25em;
    border: 1px solid #007bff52;
    border-radius: 20px;
    font-size: 0.9em;
    font-weight: 500;
    box-shadow: 0 2px 5px rgba(0, 122, 255, 0.3);
}

#tags-list {
    display: flex;
    flex-wrap: wrap;
    gap: 0.5em;
    margin: 1em 0;
}

/* Container Styling */
#recipe-info-container,
#recipe-ingredients-container,
#recipe-directions-container,
#recipe-notes-container,
#recipe-tags-container {
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
    background: linear-gradient(135deg, #f8f9fa 0%, #ffffff 100%);
    min-height: 100vh;
    padding: 2rem;
}

body {
    background: linear-gradient(135deg, #f8f9fa 0%, #ffffff 100%);
    font-family: -apple-system, BlinkMacSystemFont, 'SF Pro Display', 'Segoe UI', 'Roboto', sans-serif;
    font-size: 14rem;
    font-weight: 400;
    line-height: 1.6;
    color: #1d1d1f;
    max-width: 1200px;
    margin: 0 auto;
}

/* Responsive Design */
@media (max-width: 768px) {
    #recipe-name {
        font-size: 2em;
    }

    #recipe-info-container,
    #recipe-ingredients-container,
    #recipe-directions-container,
    #recipe-notes-container,
    #recipe-tags-container {
        padding: 1.5em;
        margin: 0.5em 0;
    }

    .recipe-directions-step::before {
        left: -0.25em;
        width: 1.5em;
        height: 1.5em;
        font-size: 0.8em;
    }
}
"""
 return css
}
