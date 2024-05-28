// swift-tools-version: 5.10
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "MediaStream",
    defaultLocalization: "en",
    platforms: [.iOS(.v15), .macOS(.v13), .visionOS(.v1), .tvOS(.v15)],
    products: [
        // Products define the executables and libraries a package produces, making them visible to other packages.
        .library(
            name: "MediaStream",
            targets: ["MediaStream"]),
    ],
    dependencies: [
      .package(url: "https://github.com/avgx/Transcoding", branch: "main"),
      .package(url: "https://github.com/avgx/Get", branch: "main"),
      .package(url: "https://github.com/apple/swift-log.git", from: "1.5.4")
    ],
    targets: [
        // Targets are the basic building blocks of a package, defining a module or a test suite.
        // Targets can depend on other targets in this package and products from dependencies.
        .target(
            name: "MediaStream", 
            dependencies: [
                "Transcoding", 
                "Get",
                .product(name: "Logging", package: "swift-log")
            ]),
        .testTarget(
            name: "MediaStreamTests",
            dependencies: [
                "MediaStream",
                .product(name: "Logging", package: "swift-log")
            ]),
    ]
)
