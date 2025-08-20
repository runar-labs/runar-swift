// swift-tools-version: 6.0
import PackageDescription

let package = Package(
	name: "swift-ffi",
	products: [
		.library(name: "RunarFFI", targets: ["RunarFFI"]),
	],
	dependencies: [
		.package(url: "https://github.com/myfreeweb/SwiftCBOR.git", from: "0.4.5")
	],
	targets: [
		.target(
			name: "CRunarFFI",
			publicHeadersPath: "include",
			cSettings: [
				.headerSearchPath("include")
			]
		),
		.target(
			name: "RunarFFI",
			dependencies: ["CRunarFFI", .product(name: "SwiftCBOR", package: "SwiftCBOR")],
			swiftSettings: [],
			linkerSettings: [
				.linkedLibrary("runar_ffi"),
				.unsafeFlags(["-L", "/Users/rafael/dev/runar-swift/runar-rust/target/debug"]) // local dev: search path for librunar_ffi.{dylib,a}
			]
		),
		.testTarget(
			name: "RunarFFITests",
			dependencies: ["RunarFFI", .product(name: "SwiftCBOR", package: "SwiftCBOR")]
		)
	]
)


