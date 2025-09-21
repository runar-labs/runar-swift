// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "swift-ffi",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .library(name: "SwiftFFI", targets: ["SwiftFFI"]),
        .library(name: "RunarFFI", targets: ["SwiftFFI"]), // Alias for backward compatibility
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
                // Prefer the FFI crate output directory (release); harmless if absent (CI)
                // Search path for the built FFI library in the workspace
                .unsafeFlags(["-Xlinker", "-L", "-Xlinker", "/Users/rafael/dev/runar-rust/target/release"]),
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "/Users/rafael/dev/runar-rust/target/release"]),
                // Also include the Cargo deps folder where the cdylib often resides
                .unsafeFlags(["-Xlinker", "-L", "-Xlinker", "/Users/rafael/dev/runar-rust/target/release/deps"]),
                .unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "/Users/rafael/dev/runar-rust/target/release/deps"]),
            ]
        ),
        .testTarget(
            name: "SwiftFFITests",
            dependencies: ["SwiftFFI", .product(name: "SwiftCBOR", package: "SwiftCBOR")],
            exclude: ["SwiftFFITests/FFIE2EIntegrationTest_baseline.swift.disabled"]
        ),
    ]
)