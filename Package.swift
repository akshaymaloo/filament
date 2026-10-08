// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Filament",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "FilamentKit",
            targets: ["FilamentKit"]
        ),
        .executable(
            name: "filament-validate",
            targets: ["FilamentValidate"]
        )
    ],
    dependencies: [],
    targets: [
        .target(
            name: "FilamentKit"
        ),
        // Synthetic fixture generation, the in-memory ZIP writer, and the
        // lightweight internal self-tests used only by `FilamentValidate` and
        // `FilamentKitTests`. Kept out of `FilamentKit` so the app and its
        // extensions never link test-only code.
        .target(
            name: "FilamentTestSupport",
            dependencies: ["FilamentKit"]
        ),
        // Standalone runnable validation suite. Usable under Command Line Tools
        // (no XCTest/swift-testing needed): `swift run filament-validate`.
        .executableTarget(
            name: "FilamentValidate",
            dependencies: ["FilamentKit", "FilamentTestSupport"]
        ),
        // Standard XCTest suite for use inside full Xcode. Not compiled by
        // `swift build`; run in Xcode or via `swift test` when XCTest is present.
        .testTarget(
            name: "FilamentKitTests",
            dependencies: ["FilamentKit", "FilamentTestSupport"]
        )
    ]
)
