// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "ClipShot",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "ClipShotKit",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "ClipShot",
            dependencies: ["ClipShotKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // Command Line Tools ship no XCTest/swift-testing, so tests run as a
        // plain executable: `swift run clipshot-selftest`
        .executableTarget(
            name: "clipshot-selftest",
            dependencies: ["ClipShotKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
