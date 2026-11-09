// swift-tools-version: 5.9
import PackageDescription
let package = Package(
    name: "TransferCore",
    platforms: [.iOS(.v16), .macOS(.v13)],
    products: [.library(name: "TransferCore", targets: ["TransferCore"]), .executable(name: "TransferProbe", targets: ["TransferProbe"])],
    dependencies: [.package(url: "https://github.com/apple/swift-nio.git", exact: "2.90.0")],
    targets: [
        .target(name: "TransferCore", dependencies: [.product(name: "NIO", package: "swift-nio"), .product(name: "NIOHTTP1", package: "swift-nio"), .product(name: "NIOWebSocket", package: "swift-nio")]),
        .executableTarget(name: "TransferProbe", dependencies: ["TransferCore"]),
        .testTarget(name: "TransferCoreTests", dependencies: ["TransferCore"])
    ]
)
