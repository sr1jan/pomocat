// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "fatcat",
    platforms: [.macOS(.v13)],
    dependencies: [
        // Swift Testing — added because the user runs Xcode Command Line Tools (no full Xcode),
        // which doesn't expose XCTest or the bundled Testing framework to SwiftPM.
        .package(url: "https://github.com/swiftlang/swift-testing.git", from: "0.10.0"),
    ],
    targets: [
        .executableTarget(name: "fatcat", path: "Sources/fatcat"),
        .testTarget(
            name: "fatcatTests",
            dependencies: [
                "fatcat",
                .product(name: "Testing", package: "swift-testing"),
            ],
            path: "Tests/fatcatTests"
        ),
    ]
)
