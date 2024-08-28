// swift-tools-version: 5.7

import PackageDescription

let package = Package(
    name: "Clairvoyant",
    platforms: [.macOS(.v12), .iOS(.v14), .watchOS(.v9)],
    products: [
        .library(name: "Clairvoyant", targets: ["Clairvoyant"]),
        .library(name: "MetricFileStorage", targets: ["MetricFileStorage"])
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-docc-plugin", from: "1.0.0"),
    ],
    targets: [
        .target(name: "Clairvoyant"),
        .target(
            name: "MetricFileStorage",
            dependencies: ["Clairvoyant"]),
        .testTarget(
            name: "ClairvoyantTests",
            dependencies: [
                "Clairvoyant",
                "MetricFileStorage",
            ]),
    ]
)
