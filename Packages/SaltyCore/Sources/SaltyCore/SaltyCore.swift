//
//  SaltyCore.swift
//  SaltyCore
//
//  Platform-independent core of Salty: the database schema and migrations, the recipe/ingredient
//  parsers, scaling, duplicate detection, HTML rendering, and the import/export formats.
//
//  What belongs here: anything with no dependency on SwiftUI, on the app's container layout, or on
//  a user-granted file location. What stays in the app: views and view models, FileHelper's
//  security-scoped bookmark handling, KeychainHelper, and RecipeImageManager — all of which are tied
//  to a specific app's sandbox rather than to recipes.
//
//  Tests live in SaltyTests (see the note in Package.swift for why they aren't a package test target).
//
//  This file is documentation only, and deliberately declares nothing. A namespace `enum SaltyCore`
//  used to live here, which turned out to shadow the module itself: `SaltyCore.Category` then resolved
//  to a member of the enum rather than the module, so a client couldn't disambiguate a type name
//  against a colliding one from the SDK (see the app's SaltyCoreTypeAliases.swift). Don't reintroduce a
//  top-level declaration named SaltyCore.
//
