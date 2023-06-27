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
                            H1(name).id("recipe-name")
                            //if author != "" { P(author).id("recipe-author") }
                            if source  != ""{ P(source).id("recipe-source") }
                            if sourceDetails != "" { P(sourceDetails).id("recipe-sourceDetails") }
                            
                            if rating != .notSet {
                                Span {
                                    Span("\(rating.rawValue)")
                                        .id("recipe-rating-raw-number")
                                    Span("/")
                                        .id("recipe-rating-raw-slash")
                                    Span("5")
                                        .id("recipe-rating-raw-max")
                                }
                                .id("recipe-rating-raw")
                            }

                            if difficulty != .notSet {
                                P("Difficulty: \(difficulty)").id("recipe-difficulty")
                            }
                            
                            if preparationTimes.count > 0 {
                                H2("Prep Time").id("recipe-prep-times")
                                Dl {
                                    for prepTime in preparationTimes {
                                        Dt(prepTime.name)
                                        //Dd(MeasurementFormatter().string(from: prepTime.time))
                                        Dd(prepTime.timeString)
                                    }
                                }.id("recipe-prep-time-list")
                            }
                        }
                        .id("recipe-info-section")

                        Section {
                            H2("Ingredients").id("recipe-ingredients-heading")
                            //if let ingredients = ingredients {
                                Ul {
                                    for ingredient in ingredients {
                                        if ingredient.isCategory {
                                            Li(ingredient.toString())
                                                .class("recipe-ingredient-category")
                                        }
                                        else {
                                            Li(ingredient.toString())
                                                .class("recipe-ingredient")
                                        }
                                    }
                                }.class("recipe-ingredients-section")
                            //}
                        }
                        .id("recipe-ingredients-section")
                        
                        Section {
                            H2("Directions").id("recipe-directions-heading")
                            Ul {
                                for direction in directions {
                                    if direction.stepName != "" {
                                        Li {
                                            Span(direction.stepName)
                                            Span(" ")
                                            Span(direction.text)
                                        }
                                        .class("recipe-directions-step-with-name")
                                    }
                                    else {
                                        Li(direction.text)
                                            .class("recipe-directions-step")
                                    }
                                }
                            }.class("recipe-directions-list")
                        }
                        .id("recipe-directions-section")
                        
                        
                        Section {
                            if notes.count > 0 {
                                H2("Notes").id("recipe-notes")
                                for note in notes {
                                    H3(note.name)
                                        .class("recipe-note-heading")
                                    P(note.text)
                                        .class("recipe-note-text")
                                }
                            }
                        }
                        .id("recipe-notes-section")
                        
                    }
                }
            }
        }
        
        let html: String = DocumentRenderer(minify: false, indent: 2).render(doc)
        print(html)
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
*::after{box-sizing:border-box;}a{text-decoration:none; color:inherit; cursor:pointer;}
button{background-color:transparent; color:inherit; border-width:0; padding:0; cursor:pointer;}
figure{margin:0;}
input::-moz-focus-inner {border:0; padding:0; margin:0;}
ul, ol, dd{margin:0; padding:0; list-style:none;}
h1, h2, h3, h4, h5, h6{margin:0; font-size:inherit; font-weight:inherit;}
p{margin:0;}
cite {font-style:normal;}
fieldset{border-width:0; padding:0; margin:0;}

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
   padding: 1rem;
   background-color: white;
   color: rgb(25,25,25);
}

a:link, a:visited {
    color: blue;
}
a:hover {
    color: cornflowerblue;
}


#recipe-info-section {
    font-size: 90%;
}

#recipe-rating::before {
    content: "Rating: ";
    
}

h1 {
    font-size: 200%;
    font-weight: bold;
    margin-top: 0.75em;
    margin-bottom: 0.75em;
}

h2 {
    font-size: 133%;
    font-weight: bold;
    margin-top: 1.5em;
    margin-bottom: 0.25em;
}

h3 {
    font-size: 105%;
    font-weight: bold;
    margin-top: 0.25em;
    margin-bottom: 0.15em;
    color: rgb(75,75,75);
}

h4 {
    font-size: 95%;
    font-weight: bold;
    margin-top: 0.1em;
    margin-bottom: 0.1em;
}
h5 {
    font-size: 90%;
    font-weight: bold;
}
h6 {
    font-size: 90%;
    font-weight: bold;
}


dl {
    padding: 0;
    margin: 0.5rem 0 0.5rem 0;
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

#recipe-notes-section {
    font-size: 90%;
}
"""
 return css
}
