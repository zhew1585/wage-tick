// swift-tools-version: 6.0
// 核心计算 (WageCore)：本产品唯一的业务逻辑模块，不依赖 AppKit、SwiftUI、文件系统、网络和系统时钟。
// 节假日数据源适配器 (HolidaySource)：读内置数据、联网获取、缓存，向核心提供节假日表；与核心分开，核心保持纯逻辑。
import PackageDescription

let package = Package(
    name: "WageCore",
    platforms: [.macOS(.v14), .iOS(.v17)],
    products: [
        .library(name: "WageCore", targets: ["WageCore"]),
        .library(name: "HolidaySource", targets: ["HolidaySource"]),
    ],
    targets: [
        .target(name: "WageCore"),
        .testTarget(name: "WageCoreTests", dependencies: ["WageCore"]),
        .target(name: "HolidaySource", dependencies: ["WageCore"]),
        .testTarget(
            name: "HolidaySourceTests",
            dependencies: ["HolidaySource", "WageCore"],
            resources: [.copy("Fixtures")]
        ),
    ]
)
