// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "MantizaTest",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        // An xtool project contains exactly one library product: the app.
        .library(
            name: "MantizaTest",
            targets: ["MantizaTest"]
        ),
    ],
    targets: [
        .target(
            name: "MantizaTest",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
