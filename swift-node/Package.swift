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
        .package(path: "../swift-ffi"),
        .package(url: "https://github.com/valpackett/SwiftCBOR.git", from: "0.5.0"),
        .package(path: "../swift-test-utils"),
    ],
    targets: [
        .target(
            name: "SwiftNode",
            dependencies: [
                .product(name: "SwiftCommon", package: "swift-common"),
                .product(name: "RunarSerializer", package: "swift-serializer"),
                .product(name: "SwiftFFI", package: "swift-ffi")
            ],
            path: "Sources/SwiftNode"
        ),
        .testTarget(
            name: "SwiftNodeTests",
            dependencies: [
                "SwiftNode",
                .product(name: "SwiftCBOR", package: "SwiftCBOR"),
                .product(name: "SwiftFFI", package: "swift-ffi")
            ],
            path: "Tests/SwiftNodeTests"
        ),
    ]
)
