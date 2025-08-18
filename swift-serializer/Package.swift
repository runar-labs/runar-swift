// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RunarSerializer",
    platforms: [
        .iOS(.v15),
        .macOS(.v13),
        .tvOS(.v15),
        .watchOS(.v8),
    ],
    products: [
        .library(
            name: "RunarSerializer",
            targets: ["RunarSerializer"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/valpackett/SwiftCBOR.git", from: "0.5.0"),
        .package(path: "../swift-serializer-macros"),
        .package(path: "../swift-common"),
    ],
    targets: [
        .target(
            name: "RunarSerializer",
            dependencies: [
                "SwiftCBOR",
                .product(name: "RunarSerializerMacros", package: "swift-serializer-macros"),
                .product(name: "SwiftCommon", package: "swift-common"),
            ],
            path: "Sources/RunarSerializer"
        ),
        .testTarget(
            name: "RunarSerializerTests",
            dependencies: [
                "RunarSerializer",
                .product(name: "RunarSerializerMacros", package: "swift-serializer-macros"),
                "SwiftCBOR",
            ],
            path: "Tests/RunarSerializerTests"
        ),
    ]
)
