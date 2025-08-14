// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "RunarTransporter",
    platforms: [
        .macOS(.v13), // Align with RunarKeys requirement
        .iOS(.v15),
        .tvOS(.v15),
        .watchOS(.v8),
    ],
    products: [
        .library(
            name: "RunarTransporter",
            targets: ["RunarTransporter"]
        ),
        .executable(name: "QuicIT", targets: ["QuicIT"]),
        .executable(name: "InteropE2E", targets: ["InteropE2E"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-crypto.git", .upToNextMajor(from: "3.14.0")),
        .package(url: "https://github.com/apple/swift-protobuf.git", from: "1.25.0"),
        .package(url: "https://github.com/valpackett/SwiftCBOR.git", from: "0.4.5"),
        .package(url: "https://github.com/apple/swift-asn1.git", .upToNextMajor(from: "1.4.0")),
        .package(url: "https://github.com/runar-labs/swift-certificates.git", branch: "feature/external-csr"),
        .package(path: "../swift-common"),
        .package(path: "../swift-keys"),
        .package(path: "../swift-serializer"),
    ],
    targets: [
        .target(
            name: "RunarTransporter",
            dependencies: [
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "SwiftProtobuf", package: "swift-protobuf"),
                .product(name: "SwiftCBOR", package: "SwiftCBOR"),
                .product(name: "SwiftCommon", package: "swift-common"),
                .product(name: "RunarKeys", package: "swift-keys"),
                // TODO: Add swift-serializer when compilation issues are resolved
                // .product(name: "RunarSerializer", package: "swift-serializer")
            ]
        ),
        .executableTarget(
            name: "QuicSample",
            dependencies: [
                .target(name: "RunarTransporter"),
                .product(name: "RunarKeys", package: "swift-keys"),
                .product(name: "SwiftCommon", package: "swift-common"),
            ]
        ),
        .executableTarget(
            name: "QuicIT",
            dependencies: [
                .target(name: "RunarTransporter"),
                .product(name: "RunarKeys", package: "swift-keys"),
                .product(name: "SwiftCommon", package: "swift-common"),
            ]
        ),
        .executableTarget(
            name: "InteropE2E",
            dependencies: [
                .target(name: "RunarTransporter"),
                .product(name: "RunarKeys", package: "swift-keys"),
                .product(name: "SwiftCommon", package: "swift-common"),
                .product(name: "SwiftASN1", package: "swift-asn1"),
                .product(name: "Crypto", package: "swift-crypto"),
                .product(name: "X509", package: "swift-certificates"),
            ]
        ),

        .testTarget(
            name: "RunarTransporterTests",
            dependencies: [
                "RunarTransporter",
                .product(name: "SwiftCBOR", package: "SwiftCBOR"),
                .product(name: "SwiftASN1", package: "swift-asn1"),
                .product(name: "X509", package: "swift-certificates"),
                .product(name: "Crypto", package: "swift-crypto"),
            ]
        ),
    ]
)

/*
 QUIC COMPATIBILITY ANALYSIS:

 Current Implementation: UDP with custom QUIC-like framing
 Rust Implementation: Quinn 0.11.x with rustls TLS

 COMPATIBILITY OPTIONS:

 1. ngtcp2 (C library with Swift bindings)
    ✅ Full QUIC protocol support
    ❌ Different TLS stack (OpenSSL vs rustls)
    ❌ Complex C bindings required
    ❌ Different certificate validation

 2. Apple Network.framework (CURRENTLY IMPLEMENTING)
    ✅ Native iOS/macOS integration
    ✅ Real QUIC protocol support
    ⚠️ Platform limited (iOS 14+, macOS 11+)
    ⚠️ Limited custom certificate validation
    ⚠️ Less control over QUIC configuration

 3. Quinn Swift Bindings (RECOMMENDED)
    ✅ Same QUIC implementation as Rust
    ✅ Same TLS stack (rustls)
    ✅ Identical certificate validation
    ✅ Full protocol compatibility
    ⚠️ Requires Quinn C API Swift bindings

 CURRENT STATUS: Implementing Network.framework QUIC transport
 for immediate real QUIC support while maintaining compatibility.
 */
