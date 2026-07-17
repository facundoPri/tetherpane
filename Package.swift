// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "TetherPane",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "AirDroidDomain", targets: ["AirDroidDomain"]),
        .library(name: "AirDroidScrcpy", targets: ["AirDroidScrcpy"]),
        .library(
            name: "TetherPaneUIFixtureSupport",
            targets: ["TetherPaneUIFixtureSupport"]
        ),
        .executable(name: "TetherPane", targets: ["AirDroidMac"]),
        .executable(name: "AirDroidMacSeamTests", targets: ["AirDroidMacSeamTests"]),
    ],
    targets: [
        .target(name: "AirDroidDomain"),
        .target(name: "AirDroidScrcpy", dependencies: ["AirDroidDomain"]),
        .target(name: "TetherPaneUIFixtureSupport"),
        .executableTarget(
            name: "AirDroidMac",
            dependencies: [
                "AirDroidDomain",
                "AirDroidScrcpy",
                "TetherPaneUIFixtureSupport",
            ]
        ),
        .executableTarget(
            name: "AirDroidMacSeamTests",
            dependencies: [
                "AirDroidDomain",
                "AirDroidScrcpy",
                "TetherPaneUIFixtureSupport",
            ]
        ),
    ]
)
