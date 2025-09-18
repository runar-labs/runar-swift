// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "swift-ffi",
    platforms: [
        .macOS(.v12)
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
                // Always search an env-configurable directory first for the static archive
                .unsafeFlags(["-L", ProcessInfo.processInfo.environment["RUNAR_FFI_LIB_DIR"] ?? "/Users/rafael/dev/runar-swift/runar-rust/target/release"]),
                // Force load static archive objects to avoid stale dylib resolution
                .unsafeFlags(["-Wl,-force_load,\(ProcessInfo.processInfo.environment[\"RUNAR_FFI_LIB_DIR\"] ?? "/Users/rafael/dev/runar-swift/runar-rust/target/release")/librunar_ffi.a"]),
                // Keep linkedLibrary for name resolution when archive not present (e.g., CI prebuilt)
                .linkedLibrary("runar_ffi"),
            ]
        ),
        .testTarget(
            name: "SwiftFFITests",
            dependencies: ["SwiftFFI", .product(name: "SwiftCBOR", package: "SwiftCBOR")]
        ),
    ]
)