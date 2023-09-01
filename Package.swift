// swift-tools-version: 5.7

import PackageDescription

let package = Package(
    name: "Clairvoyant",
    platforms: [.macOS(.v12), .iOS(.v14), .watchOS(.v9)],
    products: [
        .library(
            name: "Clairvoyant",
            targets: ["Clairvoyant"]),
        .library(
            name: "ClairvoyantVapor",
            targets: ["ClairvoyantVapor"]),
        .library(
            name: "ClairvoyantLogging",
            targets: ["ClairvoyantLogging"]),
        .library(
            name: "ClairvoyantMetrics",
            targets: ["ClairvoyantMetrics"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-metrics.git", from: "2.3.0"),
        .package(url: "https://github.com/apple/swift-log.git", from: "1.5.0"),
        .package(url: "https://github.com/vapor/vapor.git", from: "4.0.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", "1.0.0" ..< "3.0.0"),
    ],
    targets: [
        .target(
            name: "Clairvoyant",
            dependencies: [
                .product(name: "Crypto", package: "swift-crypto"),
            ]),
        .target(
            name: "ClairvoyantVapor",
            dependencies: [
                .target(name: "Clairvoyant"),
                .product(name: "Vapor", package: "vapor"),
            ]),
        .target(
            name: "ClairvoyantLogging",
            dependencies: [
                .target(name: "Clairvoyant"),
                .product(name: "Logging", package: "swift-log"),
            ]),
        .target(
            name: "ClairvoyantMetrics",
            dependencies: [
                .target(name: "Clairvoyant"),
                .product(name: "Metrics", package: "swift-metrics"),
            ]),
        .testTarget(
            name: "ClairvoyantTests",
            dependencies: [
                .product(name: "XCTVapor", package: "vapor"),
                "Clairvoyant",
                "ClairvoyantVapor",
                "ClairvoyantLogging",
                "ClairvoyantMetrics",
            ]),
    ]
)
