// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "swift-test-utils",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
    ],
    products: [
        .library(name: "RunarTestUtils", targets: ["RunarTestUtils"]),
    ],
    dependencies: [
        .package(path: "../swift-ffi"),
        .package(url: "https://github.com/valpackett/SwiftCBOR.git", from: "0.5.0"),
    ],
    targets: [
        .target(
            name: "RunarTestUtils",
            dependencies: [
                .product(name: "RunarFFI", package: "swift-ffi"),
                "SwiftCBOR",
            ],
            path: "Sources/RunarTestUtils"
        ),
        .testTarget(
            name: "RunarTestUtilsTests",
            dependencies: ["RunarTestUtils", .product(name: "RunarFFI", package: "swift-ffi"), "SwiftCBOR"],
            path: "Tests/RunarTestUtilsTests"
        ),
    ]
)
