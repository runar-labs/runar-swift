// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "swift-common",
    platforms: [
        .macOS(.v12),
        .iOS(.v15)
    ],
    products: [
        .library(
            name: "SwiftCommon",
            targets: ["SwiftCommon"]
        )
    ],
    dependencies: [],
    targets: [
        .target(
            name: "SwiftCommon",
            dependencies: []
        ),
        .testTarget(
            name: "SwiftCommonTests",
            dependencies: ["SwiftCommon"]
        )
    ]
)
