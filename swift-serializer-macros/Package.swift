// swift-tools-version: 6.0
import CompilerPluginSupport
import PackageDescription

let package = Package(
    name: "RunarSerializerMacros",
    platforms: [
        .iOS(.v15),
        .macOS(.v13),
        .tvOS(.v15),
        .watchOS(.v8),
    ],
    products: [
        .library(
            name: "RunarSerializerMacros",
            targets: ["RunarSerializerMacros"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", from: "509.0.0"),
        .package(url: "https://github.com/valpackett/SwiftCBOR.git", from: "0.4.0"),
        .package(path: "../swift-serializer"),
        .package(path: "../swift-ffi"),
    ],
    targets: [
        .target(
            name: "RunarSerializerMacros",
            dependencies: ["RunarSerializerMacrosMacros"]
        ),
        .macro(
            name: "RunarSerializerMacrosMacros",
            dependencies: [
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax"),
                .product(name: "SwiftCBOR", package: "SwiftCBOR"),
                .product(name: "RunarSerializer", package: "swift-serializer"),
                .product(name: "RunarFFI", package: "swift-ffi"),
            ]
        ),
        .testTarget(
            name: "RunarSerializerMacrosTests",
            dependencies: [
                "RunarSerializerMacros",
                .product(name: "RunarSerializer", package: "swift-serializer"),
                .product(name: "RunarFFI", package: "swift-ffi"),
            ]
        ),
    ]
)
