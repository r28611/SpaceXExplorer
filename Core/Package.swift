// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SpaceXCore",
    platforms: [.iOS("26.0"), .macOS(.v14)],
    products: [.library(name: "SpaceXCore", targets: ["SpaceXCore"])],
    targets: [
        .target(name: "SpaceXCore", resources: [.process("Fixtures")]),
        .testTarget(name: "SpaceXCoreTests", dependencies: ["SpaceXCore"])
    ]
)
