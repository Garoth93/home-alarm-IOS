// swift-tools-version: 5.9
// Logic package for the HomeAlarm app. Pure Swift (Foundation only):
// it must build and test on Linux with `swift test`.
import PackageDescription

let package = Package(
    name: "AlarmCore",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "AlarmCore", targets: ["AlarmCore"])
    ],
    targets: [
        .target(
            name: "AlarmCore",
            path: "Sources/AlarmCore"
        ),
        .testTarget(
            name: "AlarmCoreTests",
            dependencies: ["AlarmCore"],
            path: "Tests/AlarmCoreTests"
        )
    ]
)
