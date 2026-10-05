//
//  LibraryClassifierSortOrder+Label.swift
//  Salty
//

import SaltyCore

extension LibraryClassifierSortOrder {
    var label: String {
        switch self {
        case .name: "Name"
        case .mostUsed: "Most Used"
        }
    }
}
