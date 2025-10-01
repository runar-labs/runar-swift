// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "swift-common",
    platforms: [
        .macOS(.v12),
        .iOS(.v15),
    ],
    products: [
        .library(
            name: "SwiftCommon",
            targets: ["SwiftCommon"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-atomics.git", from: "1.2.0"),
    ],
    targets: [
        .target(
            name: "SwiftCommon",
            dependencies: [
                .product(name: "Atomics", package: "swift-atomics"),
            ]
        ),
        .testTarget(
            name: "SwiftCommonTests",
            dependencies: ["SwiftCommon"]
        ),
    ]
)
