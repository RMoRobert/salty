//
//  MainSheet.swift
//  Salty
//
//  The sheets a main window can present from its root, as one value: at most one is up at a time,
//  so one optional says both which it is and whether any is. The root used to thread nine Bools
//  through three levels of views and OR them together to answer the second question.
//

import Foundation
import SaltyCore

enum MainSheet: Identifiable, Hashable {
    case importFromFile
    case createFromImage
    /// iOS only: macOS opens the web importer in its own window instead. `startURL` is the page a
    /// `salty://import` link asked for; nil opens the importer on its start page.
    case createFromWeb(startURL: URL? = nil)
    case settings
    case libraryEditor(LibraryClassifier)
    case duplicateRecipes
    case consolidateDuplicates

    var id: Self { self }

    /// The web importer, whatever page it was asked to open.
    var isWebImporter: Bool {
        if case .createFromWeb = self { true } else { false }
    }

    /// The page the web importer was asked to open, if that is what this is.
    var webImportStartURL: URL? {
        if case .createFromWeb(let startURL) = self { startURL } else { nil }
    }
}
