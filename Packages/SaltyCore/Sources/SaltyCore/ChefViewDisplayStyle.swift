//
//  ChefViewDisplayStyle.swift
//  SaltyCore
//
//  How Chef View lays out a recipe's directions. Each front end decides where it stores the
//  choice and how it draws the toggle.
//

import Foundation

public enum ChefViewDisplayStyle: String, CaseIterable, Identifiable, Codable, Sendable {
    /// Every step visible at once, with the current one highlighted. The default: strict
    /// one-step-at-a-time gets in the way ("what did step 4 say?") more than it helps.
    case continuous
    /// One giant step at a time, with big tap zones. Best for TV mirroring and messy hands.
    case focus

    public var id: String { rawValue }

    public var toggled: ChefViewDisplayStyle {
        self == .continuous ? .focus : .continuous
    }
}
