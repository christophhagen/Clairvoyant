// swift-tools-version: 5.7

import PackageDescription

let package = Package(
    name: "Clairvoyant",
    platforms: [.macOS(.v12), .iOS(.v14)],
    products: [
        .library(
            name: "Clairvoyant",
            targets: ["Clairvoyant"]),
    ],
    dependencies: [
        .package(url: "https://github.com/SomeRandomiOSDev/CBORCoding", from: "1.3.0"),
        .package(url: "https://github.com/vapor/vapor.git", from: "4.0.0"),
        .package(url: "https://github.com/apple/swift-crypto.git", "1.0.0" ..< "3.0.0"),
    ],
    targets: [
        .target(
            name: "Clairvoyant",
            dependencies: [
                .product(name: "CBORCoding", package: "CBORCoding"),
                .product(name: "Crypto", package: "swift-crypto"),
            ]),
        .testTarget(
            name: "ClairvoyantTests",
            dependencies: [
                .product(name: "Vapor", package: "vapor"),
                "Clairvoyant",
            ]),
    ]
)
