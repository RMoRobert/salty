//
//  RecipePrintOptionsStorage.swift
//  Salty
//
//  Remembers the print sheet's choices between prints (and launches) as JSON in UserDefaults.
//

import Foundation
import SaltyCore

extension RecipePrintOptions {
    static let defaultsKey = "recipePrintOptions"

    /// The last-used options, or the defaults (paper size from the locale) if none were saved yet or
    /// the saved value no longer decodes.
    static func loadFromDefaults(_ defaults: UserDefaults = .standard) -> RecipePrintOptions {
        guard let data = defaults.data(forKey: defaultsKey),
              let options = try? JSONDecoder().decode(RecipePrintOptions.self, from: data) else {
            return RecipePrintOptions()
        }
        return options
    }

    func saveToDefaults(_ defaults: UserDefaults = .standard) {
        if let data = try? JSONEncoder().encode(self) {
            defaults.set(data, forKey: Self.defaultsKey)
        }
    }
}
