//
//  ChefViewDisplayStyle.swift
//  SaltyCore
//
//  How Chef View lays out a recipe's directions. Persisted with @AppStorage under
//  `ChefViewDisplayStyle.storageKey`, so it lives here (next to RecipeHtmlTheme and
//  RecipeListSortOrderSetting) rather than in the view that toggles it.
//

import Foundation

public enum ChefViewDisplayStyle: String, CaseIterable, Identifiable, Codable, Sendable {
    /// Every step visible at once, with the current one highlighted. The default: strict
    /// one-step-at-a-time gets in the way ("what did step 4 say?") more than it helps.
    case continuous
    /// One giant step at a time, with big tap zones. Best for TV mirroring and messy hands.
    case focus

    public static let storageKey = "chefViewDisplayStyle"

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .continuous: return "All Steps"
        case .focus:      return "One Step"
        }
    }

    /// SF Symbol for the in-view mode toggle.
    public var symbolName: String {
        switch self {
        case .continuous: return "list.bullet"
        case .focus:      return "rectangle.on.rectangle"
        }
    }

    public var toggled: ChefViewDisplayStyle {
        self == .continuous ? .focus : .continuous
    }
}
