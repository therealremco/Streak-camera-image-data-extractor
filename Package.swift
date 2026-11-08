// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "StreakExtractor",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "StreakExtractor", targets: ["StreakExtractor"])],
    targets: [
        .target(name: "StreakData"),
        .executableTarget(name: "StreakExtractor", dependencies: ["StreakData"]),
        .testTarget(name: "StreakDataTests", dependencies: ["StreakData"])
    ]
)
