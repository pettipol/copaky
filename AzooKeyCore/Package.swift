// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let swiftSettings: [SwiftSetting] = [
    .enableUpcomingFeature("ExistentialAny"),
    .interoperabilityMode(.Cxx),
]

let package = Package(
    name: "AzooKeyCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        // Products define the executables and libraries a package produces, and make them visible to other packages.
        .library(
            name: "SwiftUIUtils",
            targets: ["SwiftUIUtils"]
        ),
        .library(
            name: "KeyboardThemes",
            targets: ["KeyboardThemes"]
        ),
        .library(
            name: "KeyboardViews",
            targets: ["KeyboardViews"]
        ),
        .library(
            name: "AzooKeyUtils",
            targets: ["AzooKeyUtils"]
        ),
        .library(
            name: "KeyboardExtensionUtils",
            targets: ["KeyboardExtensionUtils"]
        ),
    ],
    dependencies: [
        // Dependencies declare other packages that this package depends on.
        // MARK: You must specify version which results reproductive and stable result
        // MARK: `_: .upToNextMinor(Version)` or `exact: Version` or `revision: Version`.
        // MARK: For develop branch, you can use `revision:` specification.
        // MARK: For main branch, you must use `upToNextMinor` specification.
        // Copaky: pinned to our fork, which adds `it_IT` as a keyboard language with a bundled
        // 50k-word Italian frequency lexicon (deterministic offline predictions, accent-insensitive
        // prefix match, elision support), UITextChecker as long-tail fallback. The fork branches
        // off the upstream revision 1def030b — the delta is the it_IT support only.
        // Copaky: it_IT 対応のためフォークを参照（イタリア語頻度辞書を同梱、upstream 1def030b 起点）。
        .package(url: "https://github.com/pettipol/AzooKeyKanaKanjiConverter", revision: "bb359a1512e758f0f0d6c1c3f9640ced707b0c85", traits: ["ZenzaiCPU"]),
        .package(url: "https://github.com/azooKey/CustardKit", revision: "7bddc14eb3f8f0145c6f3a4fea20cf394f8104e8"),
    ],
    targets: [
        .target(
            name: "SwiftUIUtils",
            dependencies: [
                .product(name: "SwiftUtils", package: "AzooKeyKanaKanjiConverter")
            ],
            resources: [],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "KeyboardThemes",
            dependencies: [
                "SwiftUIUtils",
                .product(name: "SwiftUtils", package: "AzooKeyKanaKanjiConverter"),
            ],
            resources: [],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "KeyboardViews",
            dependencies: [
                "SwiftUIUtils",
                "KeyboardThemes",
                "KeyboardExtensionUtils",
                .product(name: "KanaKanjiConverterModule", package: "AzooKeyKanaKanjiConverter"),
                .product(name: "CustardKit", package: "CustardKit"),
            ],
            resources: [],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "AzooKeyUtils",
            dependencies: [
                "KeyboardThemes",
                "KeyboardViews",
            ],
            resources: [],
            swiftSettings: swiftSettings
        ),
        .target(
            name: "KeyboardExtensionUtils",
            dependencies: [
                .product(name: "CustardKit", package: "CustardKit"),
                .product(name: "KanaKanjiConverterModule", package: "AzooKeyKanaKanjiConverter"),
            ],
            resources: [],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "KeyboardExtensionUtilsTests",
            dependencies: [
                "KeyboardExtensionUtils",
            ],
            swiftSettings: swiftSettings
        ),
        .testTarget(
            name: "AzooKeyUtilsTests",
            dependencies: [
                "AzooKeyUtils",
                "KeyboardViews",
            ],
            swiftSettings: swiftSettings
        ),
    ]
)
