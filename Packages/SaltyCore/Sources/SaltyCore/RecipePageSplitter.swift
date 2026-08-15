//
//  RecipePageSplitter.swift
//  Salty
//
//  Splits one multi-page document's per-page text into several recipes by page boundaries, for the
//  "this file contains multiple recipes" import flow. The user marks which pages start a new recipe;
//  contiguous pages between markers form one recipe, which is then parsed by RecipeFromTextParser.
//

import Foundation

public enum RecipePageSplitter {

    /// Groups page indices into recipes. A new group starts at page 0 and at every index in
    /// `startPages`; other pages join the group in progress. Returns one array of page indices per recipe.
    public static func groups(pageCount: Int, startPages: Set<Int>) -> [[Int]] {
        guard pageCount > 0 else { return [] }
        var result: [[Int]] = []
        for i in 0..<pageCount {
            if i == 0 || startPages.contains(i) {
                result.append([i])
            } else {
                result[result.count - 1].append(i)
            }
        }
        return result
    }

    /// Parses each page group into a Recipe, skipping groups whose pages have no text at all (e.g. a
    /// blank divider page). Pages within a group are joined with blank lines before parsing.
    public static func recipes(pageTexts: [String], startPages: Set<Int>) -> [Recipe] {
        let parser = RecipeFromTextParser()
        return groups(pageCount: pageTexts.count, startPages: startPages).compactMap { group in
            let text = group.map { pageTexts[$0] }.joined(separator: "\n\n")
            guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return parser.parseRecipe(from: text)
        }
    }
}
