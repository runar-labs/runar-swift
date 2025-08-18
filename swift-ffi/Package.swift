// swift-tools-version: 6.0
import PackageDescription

let package = Package(
	name: "swift-ffi",
	products: [
		.library(name: "RunarFFI", targets: ["RunarFFI"]),
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
			dependencies: ["CRunarFFI"],
			swiftSettings: []
		),
		.testTarget(
			name: "RunarFFITests",
			dependencies: ["RunarFFI"]
		)
	]
)


