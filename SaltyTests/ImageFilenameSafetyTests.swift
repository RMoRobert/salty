//
//  ImageFilenameSafetyTests.swift
//  SaltyTests
//
//  Recipe ids and image filenames become file names inside the images folder, and some of them
//  arrive from the sync server. `URL.appending(component:)` does not neutralise `..`, so the check
//  these tests cover is the only thing between a hostile server and a write outside that folder.
//

import Testing
import Foundation
@testable import Salty

struct ImageFilenameSafetyTests {

    @Test func ordinaryIdsAndFilenamesAreAccepted() {
        #expect(RecipeImageManager.isSafeFilenameComponent("0190B3C4-1234-7ABC-8DEF-0123456789AB"))
        #expect(RecipeImageManager.isSafeFilenameComponent("0190B3C4-1234-7ABC-8DEF-0123456789AB.jpg"))
        #expect(RecipeImageManager.isSafeFilenameComponent("r1"))
        #expect(RecipeImageManager.isSafeFilenameComponent("a..b.png"))   // dots inside a name are fine
    }

    @Test func pathTraversalIsRejected() {
        #expect(!RecipeImageManager.isSafeFilenameComponent("../../Library/Preferences/x"))
        #expect(!RecipeImageManager.isSafeFilenameComponent(".."))
        #expect(!RecipeImageManager.isSafeFilenameComponent("."))
        #expect(!RecipeImageManager.isSafeFilenameComponent("sub/dir"))
        #expect(!RecipeImageManager.isSafeFilenameComponent("sub\\dir"))
        #expect(!RecipeImageManager.isSafeFilenameComponent("/etc/passwd"))
    }

    @Test func emptyDotfileAndControlNamesAreRejected() {
        #expect(!RecipeImageManager.isSafeFilenameComponent(""))
        #expect(!RecipeImageManager.isSafeFilenameComponent(".hidden"))
        #expect(!RecipeImageManager.isSafeFilenameComponent("bad\0name"))
        #expect(!RecipeImageManager.isSafeFilenameComponent(String(repeating: "a", count: 300)))
    }

    /// The manager must refuse, not just warn, when handed an unsafe name.
    @Test func unsafeNamesNeverReachTheFilesystem() {
        #expect(RecipeImageManager.shared.saveImage(Data([0xFF, 0xD8, 0xFF, 0xE0, 0, 0, 0, 0]), for: "../escape") == nil)
        #expect(RecipeImageManager.shared.loadImage(filename: "../escape.jpg") == nil)
    }
}
