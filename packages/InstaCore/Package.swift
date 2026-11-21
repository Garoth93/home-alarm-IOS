// swift-tools-version: 5.9
// Logic package for the InstaStats app. Pure Swift (Foundation only):
// it must build and test on Linux with `swift test`.
import PackageDescription

let package = Package(
    name: "InstaCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "InstaCore", targets: ["InstaCore"])
    ],
    targets: [
        .target(
            name: "InstaCore",
            path: "Sources/InstaCore"
        ),
        .testTarget(
            name: "InstaCoreTests",
            dependencies: ["InstaCore"],
            path: "Tests/InstaCoreTests"
        )
    ]
)
