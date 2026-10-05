//
//  RecipeClassificationDraft.swift
//  Salty
//
//  The categories and tags an open recipe editor means to save. Until Save, they live here and
//  nowhere else: the editor used to write tags to the database the moment one was added and
//  categories the moment the picker was dismissed, so Cancel couldn't take either back and the
//  recipe's sync clock moved for an edit the user then threw away.
//
//  A tag typed here that the library doesn't have yet is kept by name and created on Save, so a
//  cancelled edit leaves no empty tag behind in the sidebar.
//

import Foundation
import SaltyCore

struct RecipeClassificationDraft: Equatable, Sendable {
    /// Library categories the recipe is filed under.
    var categoryIDs: Set<String> = []
    /// Library tags the recipe carries.
    var tagIDs: Set<String> = []
    /// Tags typed into this editor that no library tag matches. Created on Save, in this order.
    var newTagNames: [String] = []

    // MARK: - Display

    /// The tag names to show, sorted as the library sorts them. A selected id whose tag has since
    /// been deleted shows nothing; the writer drops it on Save.
    func tagNames(in library: [Tag]) -> [String] {
        let existing = library.filter { tagIDs.contains($0.id) }.map(\.name)
        return (existing + newTagNames)
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    /// The category names to show, sorted as the library sorts them.
    func categoryNames(in library: [Category]) -> [String] {
        library.filter { categoryIDs.contains($0.id) }
            .map(\.name)
            .sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    // MARK: - Tags

    /// Adds a tag by name. A name the library already has -- by the library's own duplicate rule,
    /// ignoring case and whitespace -- selects that tag; any other name is remembered to be created on
    /// Save. Returns false when the name is blank or the recipe already carries it.
    @discardableResult
    mutating func addTag(named name: String, library: [Tag]) -> Bool {
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        let key = LibraryDuplicateFinder.normalizedName(trimmed)
        guard !key.isEmpty else { return false }

        if let existing = library.first(where: { LibraryDuplicateFinder.normalizedName($0.name) == key }) {
            return tagIDs.insert(existing.id).inserted
        }
        guard !newTagNames.contains(where: { LibraryDuplicateFinder.normalizedName($0) == key }) else { return false }
        newTagNames.append(trimmed)
        return true
    }

    /// Removes the tag shown as `name`, whether it is a library tag or one waiting to be created.
    /// Returns whether anything was removed.
    @discardableResult
    mutating func removeTag(named name: String, library: [Tag]) -> Bool {
        let key = LibraryDuplicateFinder.normalizedName(name)
        if let index = newTagNames.firstIndex(where: { LibraryDuplicateFinder.normalizedName($0) == key }) {
            newTagNames.remove(at: index)
            return true
        }
        let matching = library.filter { LibraryDuplicateFinder.normalizedName($0.name) == key }.map(\.id)
        let before = tagIDs.count
        tagIDs.subtract(matching)
        return tagIDs.count != before
    }
}
