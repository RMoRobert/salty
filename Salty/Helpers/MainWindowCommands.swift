//
//  MainWindowCommands.swift
//  Salty
//
//  What the menu bar can ask the frontmost main window to do, and the state its items are enabled by.
//

import SwiftUI

/// Published by the main window's root view with `focusedSceneValue`, so a menu command acts on the
/// window that is actually frontmost -- see `SearchFieldFocusAction` for the pattern.
///
/// The commands used to be broadcast with `NotificationCenter` to every main window at once: ⌘N
/// opened an editor in each of them, and Print acted on each window's own selection. Windows without
/// the main view (a single recipe, Chef View, the web importer) leave this nil, which disables the
/// items -- per HIG, disabled rather than hidden.
struct MainWindowCommands {
    /// A sheet is up, so commands that would open another are disabled.
    var isAnySheetShown: Bool
    var newRecipe: @MainActor () -> Void
    var importFromFile: @MainActor () -> Void
    /// iOS only: the web importer is a sheet there and its own window on macOS.
    var createFromWeb: @MainActor () -> Void
    var exportRecipeFile: @MainActor () -> Void
    var exportHTML: @MainActor () -> Void
    var exportJSONLD: @MainActor () -> Void
    var printSelection: @MainActor () -> Void
}

extension MainWindowCommands: Equatable {
    /// Compared on state alone: the closures are rebuilt on every view update, and republishing the
    /// focused value for an identical state would redraw the menus for nothing.
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.isAnySheetShown == rhs.isAnySheetShown
    }
}

/// Published by the recipe list, which owns the selection these commands act on. Nil while the
/// frontmost window shows no recipe list (the shopping lists, another window kind).
struct RecipeSelectionCommands {
    var selectedRecipeCount: Int
    /// Heading for the menu bar's "Last Prepared Date" menu, computed from the selection.
    var lastPreparedSummary: String
    /// The list's own date-picker sheet; the root can't see it, so it is reported here.
    var isSheetShown: Bool
    var markMadeToday: @MainActor () -> Void
    var setLastMadeDate: @MainActor () -> Void
    var clearLastMade: @MainActor () -> Void
    var showInfo: @MainActor () -> Void
    /// macOS only; nil where recipes can't open in windows of their own.
    var openInNewWindows: (@MainActor () -> Void)?

    var hasSelection: Bool { selectedRecipeCount > 0 }
}

extension RecipeSelectionCommands: Equatable {
    static func == (lhs: Self, rhs: Self) -> Bool {
        lhs.selectedRecipeCount == rhs.selectedRecipeCount
            && lhs.lastPreparedSummary == rhs.lastPreparedSummary
            && lhs.isSheetShown == rhs.isSheetShown
            && (lhs.openInNewWindows == nil) == (rhs.openInNewWindows == nil)
    }
}

extension FocusedValues {
    @Entry var mainWindowCommands: MainWindowCommands?
    @Entry var recipeSelectionCommands: RecipeSelectionCommands?
}
