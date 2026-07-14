// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "AirDroidMac",
    platforms: [.macOS(.v26)],
    products: [
        .library(name: "AirDroidDomain", targets: ["AirDroidDomain"]),
        .library(name: "AirDroidScrcpy", targets: ["AirDroidScrcpy"]),
        .executable(name: "AirDroidMac", targets: ["AirDroidMac"]),
        .executable(name: "AirDroidMacSeamTests", targets: ["AirDroidMacSeamTests"]),
    ],
    targets: [
        .target(name: "AirDroidDomain"),
        .target(name: "AirDroidScrcpy", dependencies: ["AirDroidDomain"]),
        .executableTarget(
            name: "AirDroidMac",
            dependencies: ["AirDroidDomain", "AirDroidScrcpy"]
        ),
        .executableTarget(
            name: "AirDroidMacSeamTests",
            dependencies: ["AirDroidDomain", "AirDroidScrcpy"]
        ),
    ]
)
