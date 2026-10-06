// swift-tools-version: 6.2
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "IIJFetcher",
    platforms: [
        .macOS(.v13)
    ],
    targets: [
        .executableTarget(
            name: "IIJFetcher"
        ),
        .testTarget(name: "IIJFetcherTests", dependencies: ["IIJFetcher"]),
    ],
    swiftLanguageModes: [.v5]
)
