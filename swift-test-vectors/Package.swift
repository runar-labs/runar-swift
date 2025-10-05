// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "swift-test-vectors",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
    ],
    dependencies: [
        .package(name: "swift-serializer", path: "../swift-serializer"),
    ],
    targets: [
        .executableTarget(
            name: "SwiftTestVectors",
            dependencies: [
                .product(name: "RunarSerializer", package: "swift-serializer"),
            ]
        ),
    ]
)
