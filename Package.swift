// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "ThreeMFKit",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(
            name: "ThreeMFKit",
            targets: ["ThreeMFKit"]
        ),
        .executable(
            name: "three-mf-validate",
            targets: ["ThreeMFValidate"]
        )
    ],
    dependencies: [],
    targets: [
        .target(
            name: "ThreeMFKit"
        ),
        // Standalone runnable validation suite. Usable under Command Line Tools
        // (no XCTest/swift-testing needed): `swift run three-mf-validate`.
        .executableTarget(
            name: "ThreeMFValidate",
            dependencies: ["ThreeMFKit"]
        ),
        // Standard XCTest suite for use inside full Xcode. Not compiled by
        // `swift build`; run in Xcode or via `swift test` when XCTest is present.
        .testTarget(
            name: "ThreeMFKitTests",
            dependencies: ["ThreeMFKit"]
        )
    ]
)
