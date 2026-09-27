//
//  LibraryFilenames.swift
//  SaltyCore
//

/// Rules for names that become files inside a library folder.
public enum LibraryFilenames {
    /// Whether `name` can be used as a single file name inside the images directory.
    /// Ids and filenames can arrive from the sync server, and `URL.appending(component:)` does not
    /// neutralise `..`, so anything that could escape the folder or hide as a dotfile is refused.
    public static func isSafeComponent(_ name: String) -> Bool {
        guard !name.isEmpty, name.utf8.count <= 255 else { return false }
        guard !name.hasPrefix(".") else { return false }
        return !name.contains("/") && !name.contains("\\") && !name.contains("\0")
    }
}
