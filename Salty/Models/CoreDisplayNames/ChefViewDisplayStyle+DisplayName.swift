//
//  ChefViewDisplayStyle+DisplayName.swift
//  Salty
//

import SaltyCore

extension ChefViewDisplayStyle {
    var displayName: String {
        switch self {
        case .continuous: "All Steps"
        case .focus: "One Step"
        }
    }
}
