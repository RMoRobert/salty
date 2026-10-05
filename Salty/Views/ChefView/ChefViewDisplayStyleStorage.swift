//
//  ChefViewDisplayStyleStorage.swift
//  Salty
//
//  The @AppStorage key for Chef View's display style. ChefView and the external-display Chef View
//  both bind to it, so a change in one shows in the other.
//

import Foundation
import SaltyCore

extension ChefViewDisplayStyle {
    static let storageKey = "chefViewDisplayStyle"
}
