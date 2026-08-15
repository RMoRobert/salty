// swift-tools-version: 6.2

import PackageDescription

// Platform minimums intentionally mirror the app's IPHONEOS_DEPLOYMENT_TARGET / MACOSX_DEPLOYMENT_TARGET
// so availability checks behave identically on both sides of the module boundary. When a tvOS target is
// added, declare `.tvOS(...)` here too — but only once something actually builds for it, so the platform
// list never claims support that has never been compiled.
let package = Package(
    name: "SaltyCore",
    platforms: [
        .iOS("18.6"),
        .macOS("15.6"),
    ],
    products: [
        .library(name: "SaltyCore", targets: ["SaltyCore"]),
    ],
    dependencies: [
        // URLs match Salty.xcodeproj's XCRemoteSwiftPackageReference entries exactly (including the
        // trailing slash on sqlite-data). SPM keys packages by identity rather than raw URL, but keeping
        // them identical avoids any chance of the same dependency resolving twice in the app's graph.
        .package(url: "https://github.com/pointfreeco/sqlite-data/", from: "1.0.0"),
        .package(url: "https://github.com/swiftlang/swift-markdown", "0.8.0" ..< "2.0.0"),
        .package(url: "https://github.com/mhayes853/swift-uuidv7", from: "0.4.0"),
        // GRDB arrives transitively through sqlite-data, and Xcode's search paths make it importable
        // without this line -- but Schema.swift names `GRDB.Database` directly, so depending on it
        // explicitly is what actually makes that legal rather than incidental. `from: "7.6.0"` matches
        // sqlite-data's own requirement, so the two unify on one copy instead of resolving twice.
        .package(url: "https://github.com/groue/GRDB.swift", from: "7.6.0"),
        .package(url: "https://github.com/BinaryBirds/swift-html", from: "1.7.0"),
        .package(url: "https://github.com/scinfu/SwiftSoup.git", from: "2.9.5"),
    ],
    // NOTE: deliberately no test target here. Salty.xcodeproj has no *shared* schemes — they're
    // autocreated and live in gitignored xcuserdata — so `xcodebuild test -scheme Salty` can only see
    // targets belonging to the project itself. A package test target would be invisible to that command
    // (and to CI), which is a silent loss of coverage. SaltyCore's tests therefore stay in SaltyTests,
    // which imports this module normally. If shared schemes are ever added, moving the pure-logic tests
    // into a target here would make them runnable via a plain `swift test`.
    targets: [
        .target(
            name: "SaltyCore",
            dependencies: [
                .product(name: "SQLiteData", package: "sqlite-data"),
                .product(name: "Markdown", package: "swift-markdown"),
                .product(name: "UUIDV7", package: "swift-uuidv7"),
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "SwiftHtml", package: "swift-html"),
                .product(name: "SwiftSoup", package: "SwiftSoup"),
            ]
        ),
    ]
)
