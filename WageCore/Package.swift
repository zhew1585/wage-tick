// swift-tools-version: 6.0
// 核心计算：本产品唯一的业务逻辑模块，不依赖 AppKit、SwiftUI、文件系统、网络和系统时钟。
import PackageDescription

let package = Package(
    name: "WageCore",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "WageCore", targets: ["WageCore"]),
    ],
    targets: [
        .target(name: "WageCore"),
        .testTarget(name: "WageCoreTests", dependencies: ["WageCore"]),
    ]
)
