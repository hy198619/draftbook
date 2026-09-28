// swift-tools-version: 5.10

import PackageDescription

let package = Package(
    name: "DraftBook",
    defaultLocalization: "zh-Hans",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "DraftBookCore", targets: ["DraftBookCore"]),
        .executable(name: "DraftBook", targets: ["DraftBook"])
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-markdown.git", exact: "0.5.0")
    ],
    targets: [
        .target(name: "DraftBookCore"),
        .executableTarget(
            name: "DraftBook",
            dependencies: ["DraftBookCore", .product(name: "Markdown", package: "swift-markdown")]
        ),
        .testTarget(
            name: "DraftBookEditorTests",
            dependencies: ["DraftBook", .product(name: "Markdown", package: "swift-markdown")]
        ),
        .testTarget(
            name: "DraftBookCoreTests",
            dependencies: ["DraftBookCore"]
        )
    ]
)
