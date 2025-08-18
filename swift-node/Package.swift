// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "SwiftNode",
    platforms: [
        .iOS(.v15),
        .macOS(.v13),
        .tvOS(.v15),
        .watchOS(.v8),
    ],
    products: [
        .library(
            name: "SwiftNode",
            targets: ["SwiftNode"]
        ),
    ],
    dependencies: [
        .package(path: "../swift-common"),
        .package(path: "../swift-serializer"),
    ],
    targets: [
        .target(
            name: "SwiftNode",
            dependencies: [
                .product(name: "SwiftCommon", package: "swift-common"),
                .product(name: "RunarSerializer", package: "swift-serializer"),
            ],
            path: "Sources/SwiftNode"
        ),
        .testTarget(
            name: "SwiftNodeTests",
            dependencies: ["SwiftNode"],
            path: "Tests/SwiftNodeTests"
        ),
    ]
)
