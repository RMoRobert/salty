//
//  RecipePrintOptions+DisplayNames.swift
//  Salty
//
//  The print options sheet's names for paper sizes, orientations and colour modes.
//

import SaltyCore

extension RecipePrintOptions.PaperSize {
    var displayName: String {
        switch self {
        case .letter: "US Letter"
        case .legal: "US Legal"
        case .a4: "A4"
        case .a5: "A5"
        }
    }
}

extension RecipePrintOptions.Orientation {
    var displayName: String {
        switch self {
        case .portrait: "Portrait"
        case .landscape: "Landscape"
        }
    }
}

extension RecipePrintOptions.ColorMode {
    var displayName: String {
        switch self {
        case .color: "Color"
        case .blackText: "Black Text"
        case .grayscale: "Grayscale"
        }
    }
}
