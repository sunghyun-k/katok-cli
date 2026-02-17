// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "messages-cli",
    platforms: [.macOS(.v13)],
    dependencies: [
        .package(url: "https://github.com/sunghyun-k/axkit", from: "0.2.0"),
        .package(url: "https://github.com/apple/swift-argument-parser", from: "1.7.0"),
    ],
    targets: [
        .executableTarget(
            name: "Katok",
            dependencies: [
                .product(name: "AXKit", package: "axkit"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
        ),
    ],
)
