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
        .package(url: "https://github.com/runar-labs/swift-certificates.git", branch: "feature/external-csr"),
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


