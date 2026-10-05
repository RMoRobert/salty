//
//  MainSheet.swift
//  Salty
//
//  The sheets a main window can present from its root, as one value: at most one is up at a time,
//  so one optional says both which it is and whether any is. The root used to thread nine Bools
//  through three levels of views and OR them together to answer the second question.
//

import SaltyCore

enum MainSheet: Identifiable, Hashable {
    case importFromFile
    case createFromImage
    /// iOS only: macOS opens the web importer in its own window instead.
    case createFromWeb
    case settings
    case libraryEditor(LibraryClassifier)
    case duplicateRecipes
    case consolidateDuplicates

    var id: Self { self }
}
