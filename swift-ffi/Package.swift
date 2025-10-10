// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "swift-ffi",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
    ],
    products: [
        .library(name: "SwiftFFI", targets: ["SwiftFFI"]),
    ],
    dependencies: [
        .package(url: "https://github.com/valpackett/SwiftCBOR.git", from: "0.5.0"),
        .package(path: "../swift-common"),
    ],
    targets: [
        .target(
            name: "CRunarFFI",
            publicHeadersPath: "include",
            cSettings: [
                .headerSearchPath("include"),
            ]
        ),
        .target(
            name: "SwiftFFI",
            dependencies: ["CRunarFFI", .product(name: "SwiftCommon", package: "swift-common"), .product(name: "SwiftCBOR", package: "SwiftCBOR")],
            swiftSettings: [],
            linkerSettings: [
                .linkedLibrary("runar_ffi"),
                // Use the copied library in the Swift package
                .unsafeFlags(["-Xlinker", "-L", "-Xlinker", "./lib"]),
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "./lib"]),
                // Fallback to Rust workspace (for development)
                .unsafeFlags(["-Xlinker", "-L", "-Xlinker", "/Users/rafael/dev/runar-rust/target/release"]),
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "/Users/rafael/dev/runar-rust/target/release"]),
                .unsafeFlags(["-Xlinker", "-L", "-Xlinker", "/Users/rafael/dev/runar-rust/target/release/deps"]),
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "/Users/rafael/dev/runar-rust/target/release/deps"]),
            ]
        ),
        .testTarget(
            name: "SwiftFFITests",
            dependencies: ["SwiftFFI", .product(name: "SwiftCBOR", package: "SwiftCBOR")],
            exclude: [],
            linkerSettings: [
                .linkedLibrary("runar_ffi"),
                // Use the copied library in the Swift package
                .unsafeFlags(["-Xlinker", "-L", "-Xlinker", "./lib"]),
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "./lib"]),
                // Fallback to Rust workspace (for development)
                .unsafeFlags(["-Xlinker", "-L", "-Xlinker", "/Users/rafael/dev/runar-rust/target/release"]),
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "/Users/rafael/dev/runar-rust/target/release"]),
                .unsafeFlags(["-Xlinker", "-L", "-Xlinker", "/Users/rafael/dev/runar-rust/target/release/deps"]),
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "/Users/rafael/dev/runar-rust/target/release/deps"]),
            ]
        ),
    ]
)
