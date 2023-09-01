// swift-tools-version: 5.7

import PackageDescription

let package = Package(
    name: "Clairvoyant",
    platforms: [.macOS(.v12), .iOS(.v14), .watchOS(.v9)],
    products: [
        .library(
            name: "Clairvoyant",
            targets: ["Clairvoyant"]),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-crypto.git", "1.0.0" ..< "3.0.0"),
    ],
    targets: [
        .target(
            name: "Clairvoyant",
            dependencies: [
                .product(name: "Crypto", package: "swift-crypto"),
            ]),
        .testTarget(
            name: "ClairvoyantTests",
            dependencies: [
                "Clairvoyant",
            ]),
    ]
)
