// swift-tools-version: 6.0

import PackageDescription

// The widget binary must already carry a (placeholder) signature block when xtool signs it:
// without one, signing failed with "Can't find free space of LoadCommands for CodeSignature".
// The app gets one from the linker by default; the extension needs to ask for it.
let headerRoom: [LinkerSetting] = [.unsafeFlags(["-Xlinker", "-headerpad_max_install_names",
                                                 "-Xlinker", "-adhoc_codesign"])]

// xtool links extensions with Foundation's _NSExtensionMain as the entry point, so nothing refers to
// the widget's own @main and the linker threw all of its code away (an empty widget that iOS never
// lists). Keeping _main pulls the widget in; the entry point stays _NSExtensionMain.
// Drop this once xtool keeps an extension's own code by itself.
let keepWidgetCode: [LinkerSetting] = [.unsafeFlags(["-Xlinker", "-u", "-Xlinker", "_main"])]

let package = Package(
    name: "Mantiza",
    platforms: [
        .iOS("27.0"),  // ScreenCaptureKit on iPhone needs iOS 27
        .macOS(.v14),
    ],
    products: [
        // xtool: the app product (xtool.yml "product") and the widget extension (xtool.yml "extensions").
        .library(name: "Mantiza", targets: ["Mantiza"]),
        .library(name: "MantizaWidget", targets: ["MantizaWidget"]),
    ],
    targets: [
        // Look and shared data used by both: colours, pixel logo and animations, App Group storage.
        .target(name: "MantizaKit", swiftSettings: [.swiftLanguageMode(.v5)]),
        .target(name: "Mantiza", dependencies: ["MantizaKit"], swiftSettings: [.swiftLanguageMode(.v5)],
                linkerSettings: headerRoom),
        .target(name: "MantizaWidget", dependencies: ["MantizaKit"], swiftSettings: [.swiftLanguageMode(.v5)],
                linkerSettings: headerRoom + keepWidgetCode),
    ]
)
