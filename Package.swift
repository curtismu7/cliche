// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "Cliche",
    platforms: [.macOS(.v14)],
    targets: [
        .target(
            name: "ClicheKit",
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        .executableTarget(
            name: "Cliche",
            dependencies: ["ClicheKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
        // Command Line Tools ship no XCTest/swift-testing, so tests run as a
        // plain executable: `swift run cliche-selftest`
        .executableTarget(
            name: "cliche-selftest",
            dependencies: ["ClicheKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]
        ),
    ]
)
