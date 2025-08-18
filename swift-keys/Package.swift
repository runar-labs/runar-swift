// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "RunarKeys",
    platforms: [
        .iOS(.v15), .macOS(.v13)
    ],
    products: [
        .library(name: "RunarKeys", targets: ["RunarKeys"]),
    ],
    dependencies: [
        // Use vendored swift-certificates during local development to avoid missing remote branch
        .package(path: "../Vendor/swift-certificates"),
    ],
    targets: [
        .target(
            name: "RunarKeys",
            dependencies: [
                .product(name: "X509", package: "swift-certificates"),
            ],
            path: "Sources/RunarKeys"
        ),
        .testTarget(
            name: "RunarKeysTests",
            dependencies: ["RunarKeys"],
            path: "Tests/RunarKeysTests"
        ),
    ]
)


