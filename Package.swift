// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "fatcat",
    // macOS 14 is required by VNGenerateForegroundInstanceMaskRequest, which the
    // make-cat-asset tool uses to extract the cat from a green-screen source.
    platforms: [.macOS(.v14)],
    dependencies: [
        // Swift Testing — added because the user runs Xcode Command Line Tools (no full Xcode).
        // The Swift 6 toolchain ships Testing.framework on disk but not its internal companion
        // module (_TestingInternals), so `import Testing` fails without this package dep.
        .package(url: "https://github.com/swiftlang/swift-testing.git", from: "0.10.0"),
    ],
    targets: [
        .executableTarget(name: "fatcat", path: "Sources/fatcat"),
        .executableTarget(name: "make-cat-asset", path: "Sources/make-cat-asset"),
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
