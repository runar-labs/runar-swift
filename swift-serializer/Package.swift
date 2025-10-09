// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RunarSerializer",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
    ],
    products: [
        .library(
            name: "RunarSerializer",
            targets: ["RunarSerializer"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/valpackett/SwiftCBOR.git", from: "0.5.0"),
        .package(path: "../swift-common"),
        .package(path: "../swift-ffi"),
        .package(path: "../swift-serializer-macros"),
    ],
    targets: [
        .target(
            name: "RunarSerializer",
            dependencies: [
                "SwiftCBOR",
                .product(name: "SwiftCommon", package: "swift-common"),
                .product(name: "SwiftFFI", package: "swift-ffi"),
            ],
            path: "Sources/RunarSerializer"
        ),
        .testTarget(
            name: "RunarSerializerTests",
            dependencies: [
                "RunarSerializer",
                "SwiftCBOR",
                .product(name: "SwiftFFI", package: "swift-ffi"),
                .product(name: "RunarSerializerMacros", package: "swift-serializer-macros"),
            ],
            path: "Tests/RunarSerializerTests"
        ),
    ]
)
