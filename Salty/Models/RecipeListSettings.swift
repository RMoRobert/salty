//
//  RecipeListSettings.swift
//  Salty
//
//  How the recipe list is sorted and which fields are searched. These are app-wide (shared by
//  all windows/tabs) and persisted in `UserDefaults` under the keys the rest of the
//  Salty clients share, so one observable object owns them: the menu bar, the iOS "More" menu and
//  every main window's view model read and write this instance, and observation carries a change
//  from one to the others. The views used to each read `UserDefaults` directly and listen for
//  `UserDefaults.didChangeNotification` -- which fires for *every* defaults write in the process --
//  through block observers that `removeObserver(self)` never removed.
//
//  Only this type touches the keys. SaltyCore keeps the enums and the key names
//  (`RecipeListSortOrderSetting`, `RecipeListSearchOptions.userDefaultsKey`) so other front ends
//  store the same values under the same names in their own settings stores. This is basically a
//  way to left SwiftUI keep using AppStorage while allowing flexibility for others in future in case
//  names can be re-used there.

import Foundation
import Observation
import SaltyCore

@Observable
@MainActor
final class RecipeListSettings {
    static let shared = RecipeListSettings()

    static let sortOrderKey = "recipeListSortOrder"
    static let sortDirectionKey = "recipeListSortDirection"

    @ObservationIgnored
    private let defaults: UserDefaults

    var sortOrder: RecipeListSortOrderSetting {
        didSet { defaults.set(sortOrder.rawValue, forKey: Self.sortOrderKey) }
    }

    var sortDirection: RecipeListSortDirection {
        didSet { defaults.set(sortDirection.rawValue, forKey: Self.sortDirectionKey) }
    }

    /// The fields a search looks in. Never empty: the last one can't be turned off, so a search
    /// always matches something. Name alone when nothing has been chosen yet.
    private(set) var searchOptions: Set<RecipeListSearchOptions>

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        sortOrder = defaults.string(forKey: Self.sortOrderKey)
            .flatMap(RecipeListSortOrderSetting.init(rawValue:)) ?? .byName
        sortDirection = defaults.string(forKey: Self.sortDirectionKey)
            .flatMap(RecipeListSortDirection.init(rawValue:)) ?? .ascending
        let stored = Set(RecipeListSearchOptions.allCases.filter { defaults.bool(forKey: $0.userDefaultsKey) })
        searchOptions = stored.isEmpty ? [.name] : stored
    }

    /// Writes every field's state, so the stored picture is complete even for a field that was only
    /// ever on by default and never toggled.
    private func persistSearchOptions() {
        for option in RecipeListSearchOptions.allCases {
            defaults.set(searchOptions.contains(option), forKey: option.userDefaultsKey)
        }
    }

    func isSearching(_ option: RecipeListSearchOptions) -> Bool {
        searchOptions.contains(option)
    }

    /// Turns a search field on or off. Turning off the only remaining field is ignored.
    func setSearching(_ option: RecipeListSearchOptions, _ isOn: Bool) {
        if isOn {
            guard searchOptions.insert(option).inserted else { return }
        } else {
            guard searchOptions.count > 1, searchOptions.remove(option) != nil else { return }
        }
        persistSearchOptions()
    }

    /// Everything here that changes which rows the list shows, in one string, for a `task(id:)`.
    var queryKey: String {
        let options = RecipeListSearchOptions.allCases.map { searchOptions.contains($0) ? "1" : "0" }.joined()
        return "\(sortOrder.rawValue)|\(sortDirection.rawValue)|\(options)"
    }
}
