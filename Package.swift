// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "ClipFlow",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "ClipFlow", targets: ["ClipFlow"])
    ],
    targets: [
        .executableTarget(
            name: "ClipFlow",
            path: "Sources"
        )
    ]
)
