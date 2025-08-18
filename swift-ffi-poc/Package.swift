// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SwiftFFIPOC",
    platforms: [
        .macOS(.v13),
        .iOS(.v16)
    ],
    products: [
        .library(
            name: "SwiftFFIPOC",
            targets: ["SwiftFFIPOC"]),
        .executable(
            name: "FFIPOCDemo",
            targets: ["FFIPOCDemo"]),
    ],
    dependencies: [
        .package(url: "https://github.com/valpackett/SwiftCBOR.git", from: "0.5.0"),
    ],
    targets: [
        .target(
            name: "SwiftFFIPOC",
            dependencies: ["SwiftCBOR"],
            path: "Sources/SwiftFFIPOC"),
        .executableTarget(
            name: "FFIPOCDemo",
            dependencies: ["SwiftFFIPOC", "SwiftCBOR"],
            path: "Sources/FFIPOCDemo"),
        .testTarget(
            name: "SwiftFFIPOCTests",
            dependencies: ["SwiftFFIPOC"],
            path: "Tests/SwiftFFIPOCTests"),
    ]
)
