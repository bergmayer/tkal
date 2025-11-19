// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "tkal",
    platforms: [
        .macOS(.v12)
    ],
    products: [
        .executable(
            name: "tkal",
            targets: ["tkal"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/apple/swift-argument-parser.git", from: "1.3.0"),
    ],
    targets: [
        .target(
            name: "NCursesBridge",
            path: "Sources/NCursesBridge",
            publicHeadersPath: "."
        ),
        .executableTarget(
            name: "tkal",
            dependencies: [
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
                "NCursesBridge",
            ],
            path: "Sources/tkal"
        ),
    ]
)
