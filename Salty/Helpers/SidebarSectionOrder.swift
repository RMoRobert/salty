//
//  SidebarSectionOrder.swift
//  Salty
//
//  Which sidebar sections are shown, and in what order.
//
//  The Library section (All Recipes, Favorites, Want to Make) is pinned to the top of the sidebar, so only
//  the sections below it -- Categories, Courses, Tags, Shopping Lists -- take part here. The order lives in
//  one UserDefaults string; visibility keeps the per-section keys it has always used, so preferences set
//  before ordering existed carry over untouched.
//

import Foundation

/// A sidebar section the user can both hide and reorder.
enum SidebarSection: String, CaseIterable, Identifiable, Sendable {
    case categories, courses, tags, shoppingLists

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .categories: return "Categories"
        case .courses: return "Courses"
        case .tags: return "Tags"
        case .shoppingLists: return "Shopping Lists"
        }
    }

    /// Icon shown beside the section's name in Settings. (The sidebar itself labels the section with a
    /// header rather than an icon; these are for the settings rows and menu items.)
    var systemImage: String {
        switch self {
        case .categories: return "rectangle.stack"
        case .courses: return "fork.knife"
        case .tags: return "tag"
        case .shoppingLists: return "cart"
        }
    }

    /// UserDefaults key holding this section's show/hide state.
    var visibilityKey: String {
        switch self {
        case .categories: return "sidebarShowCategories"
        case .courses: return "sidebarShowCourses"
        case .tags: return "sidebarShowTags"
        case .shoppingLists: return "sidebarShowShoppingLists"
        }
    }

    /// Sections start out visible, so a key that has never been written reads as shown.
    func isVisible(in defaults: UserDefaults = .standard) -> Bool {
        defaults.object(forKey: visibilityKey) == nil || defaults.bool(forKey: visibilityKey)
    }
}

enum SidebarSectionOrder {
    /// UserDefaults key for the stored order: section raw values, comma-separated.
    static let storageKey = "sidebarSectionOrder"

    /// Arrangement used until the user reorders anything -- the order the sidebar has always had.
    static let defaultOrder: [SidebarSection] = [.categories, .courses, .tags, .shoppingLists]

    /// Sections that can't all be hidden at once: with Categories, Courses, and Tags all off, the sidebar
    /// would be little more than All Recipes.
    static let mutuallyRequired: [SidebarSection] = [.categories, .courses, .tags]

    /// Stored order, repaired on the way out: unknown and duplicate entries are dropped, and any section
    /// the stored value doesn't mention (one added in a later version) is appended in default order.
    static func decode(_ raw: String) -> [SidebarSection] {
        var order: [SidebarSection] = []
        for name in raw.split(separator: ",") {
            guard let section = SidebarSection(rawValue: String(name)), !order.contains(section) else { continue }
            order.append(section)
        }
        order.append(contentsOf: defaultOrder.filter { !order.contains($0) })
        return order
    }

    static func encode(_ order: [SidebarSection]) -> String {
        order.map(\.rawValue).joined(separator: ",")
    }

    static func load(from defaults: UserDefaults = .standard) -> [SidebarSection] {
        decode(defaults.string(forKey: storageKey) ?? "")
    }

    static func save(_ order: [SidebarSection], to defaults: UserDefaults = .standard) {
        defaults.set(encode(order), forKey: storageKey)
    }

    /// Drag-reorder result, for `ForEach`'s `onMove` handler.
    static func moved(_ order: [SidebarSection], fromOffsets: IndexSet, toOffset: Int) -> [SidebarSection] {
        var order = order
        order.move(fromOffsets: fromOffsets, toOffset: toOffset)
        return order
    }

    /// One step up (-1) or down (+1), for the arrow buttons. A move past either end is a no-op rather than
    /// a wrap-around, so the buttons at the ends simply do nothing.
    static func moved(_ order: [SidebarSection], _ section: SidebarSection, by delta: Int) -> [SidebarSection] {
        guard let index = order.firstIndex(of: section) else { return order }
        let destination = index + delta
        guard order.indices.contains(destination) else { return order }
        var order = order
        order.swapAt(index, destination)
        return order
    }

    /// Whether `section` may be hidden: one of Categories, Courses, and Tags always has to stay visible.
    /// Takes the visibility lookup rather than reading it, so the rule can be exercised without a
    /// UserDefaults suite.
    static func canHide(_ section: SidebarSection, isVisible: (SidebarSection) -> Bool) -> Bool {
        guard mutuallyRequired.contains(section) else { return true }
        return mutuallyRequired.contains { $0 != section && isVisible($0) }
    }

    static func canHide(_ section: SidebarSection, in defaults: UserDefaults = .standard) -> Bool {
        canHide(section) { $0.isVisible(in: defaults) }
    }

    /// Applies a show/hide change, ignoring the one change that would leave Categories, Courses, and Tags
    /// all hidden. Every toggle in the app (Settings, the Sidebar Items menu) writes through here, so the
    /// rule holds no matter where it's flipped.
    static func setVisible(_ isVisible: Bool, for section: SidebarSection, in defaults: UserDefaults = .standard) {
        guard isVisible || canHide(section, in: defaults) else { return }
        defaults.set(isVisible, forKey: section.visibilityKey)
    }
}
