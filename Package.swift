// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "SmartClip",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.0.0"),
        .package(url: "https://github.com/sparkle-project/Sparkle.git", from: "2.5.0"),
    ],
    targets: [
        .executableTarget(
            name: "SmartClip",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "SmartClip",
            exclude: ["Info.plist"],
            resources: [
                .process("Resources"),
            ]
        ),
        .testTarget(
            name: "SmartClipTests",
            dependencies: ["SmartClip"],
            path: "SmartClipTests"
        ),
    ]
)
