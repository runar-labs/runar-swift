// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "runar-swift",
    platforms: [
        .macOS(.v12),
        .iOS(.v15),
        .tvOS(.v15),
        .watchOS(.v8)
    ],
    products: [],
    dependencies: [
        .package(path: "swift-common"),
        .package(path: "swift-keys"),
        .package(path: "swift-serializer-macros"),
        .package(path: "swift-serializer"),
        .package(path: "swift-transporter"),
    ],
    targets: []
)
