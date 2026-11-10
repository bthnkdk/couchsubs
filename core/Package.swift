// swift-tools-version: 6.2
// SPDX-License-Identifier: AGPL-3.0-only

import PackageDescription

let package = Package(
    name: "CouchSubsCore",
    platforms: [.macOS(.v26), .iOS(.v26)],
    products: [
        .library(name: "CouchSubsCore", targets: ["CouchSubsCore"]),
    ],
    targets: [
        .target(name: "CouchSubsCore", resources: [.copy("Resources/obs-overlay.html"), .copy("Resources/glossary-en-tr.json")], swiftSettings: [.swiftLanguageMode(.v5)]),
        .executableTarget(name: "tv-smoke", dependencies: ["CouchSubsCore"], swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(name: "CouchSubsCoreTests", dependencies: ["CouchSubsCore"], swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
