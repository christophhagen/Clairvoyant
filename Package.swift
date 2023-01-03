// swift-tools-version: 5.7

import PackageDescription

let package = Package(
    name: "Clairvoyant",
    platforms: [.macOS(.v12)],
    products: [
        .library(
            name: "Clairvoyant",
            targets: ["Clairvoyant"]),
    ],
    dependencies: [
        .package(url: "https://github.com/SomeRandomiOSDev/CBORCoding", from: "1.3.0"),
        .package(url: "https://github.com/vapor/vapor.git", from: "4.0.0"),
    ],
    targets: [
        .target(
            name: "Clairvoyant",
            dependencies: [
                .product(name: "CBORCoding", package: "CBORCoding"),
                .product(name: "Vapor", package: "vapor")
            ]),
        .testTarget(
            name: "ClairvoyantTests",
            dependencies: ["Clairvoyant"]),
    ]
)
