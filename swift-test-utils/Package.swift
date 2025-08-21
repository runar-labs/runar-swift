// swift-tools-version: 5.10
import PackageDescription

let package = Package(
    name: "swift-test-utils",
    platforms: [
        .iOS(.v15), .macOS(.v13),
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
