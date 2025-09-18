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
                .linkedLibrary("runar_ffi"),
                .unsafeFlags(["-L", "/Users/rafael/dev/runar-swift/runar-rust/target/release"]), // local dev: search path for librunar_ffi.{dylib,a}
            ]
        ),
        .testTarget(
            name: "SwiftFFITests",
            dependencies: ["SwiftFFI", .product(name: "SwiftCBOR", package: "SwiftCBOR")]
        ),
    ]
)