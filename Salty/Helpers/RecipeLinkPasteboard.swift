//
//  RecipeLinkPasteboard.swift
//  Salty
//
//  Copy Private Link: puts a recipe's `salty://recipe/<id>` link on the clipboard, for a note, a
//  calendar event, a to-do or a script to open the recipe from later.
//
//  "Private" because the link only resolves in this library -- on your own devices, once the recipe
//  has synced to them; anyone else's Salty says the recipe isn't there. That is also why it sits with
//  Get Info rather than beside Share and Export, which do hand the recipe itself to someone else (the
//  same split as 1Password's "Copy Private Link" vs. Share). Shortcuts reaches the same link through
//  `RecipeEntity.privateLink`.
//

import Foundation
#if os(macOS)
import AppKit
#else
import UIKit
import UniformTypeIdentifiers
#endif

enum RecipeLinkPasteboard {
    /// Replaces the clipboard with the private link to `recipeId`, as both a URL (so Notes, Mail and
    /// Reminders paste a tappable link) and plain text (so a text field pastes the address).
    @MainActor
    static func copyPrivateLink(forRecipeId recipeId: String) {
        let link = SaltyURL.recipe(id: recipeId).url
        #if os(macOS)
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.setString(link.absoluteString, forType: .URL)
        pasteboard.setString(link.absoluteString, forType: .string)
        #else
        UIPasteboard.general.setItems([[
            UTType.url.identifier: link,
            UTType.plainText.identifier: link.absoluteString
        ]])
        #endif
    }
}
