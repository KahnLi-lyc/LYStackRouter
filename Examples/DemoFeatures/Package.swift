// swift-tools-version: 6.1
import PackageDescription

// 示例 App 的业务模块。每个模块是独立的 SwiftPM target，只依赖共享的路由定义，互不引用。
let package = Package(
    name: "DemoFeatures",
    platforms: [.iOS(.v16)],
    products: [
        .library(name: "DemoRoutes", targets: ["DemoRoutes"]),
        .library(name: "DemoCommunity", targets: ["DemoCommunity"]),
        .library(name: "DemoMessages", targets: ["DemoMessages"])
    ],
    dependencies: [
        .package(path: "../..")
    ],
    targets: [
        .target(name: "DemoRoutes", dependencies: [.product(name: "LYStackRouter", package: "LYStackRouter")]),
        .target(
            name: "DemoCommunity",
            dependencies: ["DemoRoutes", .product(name: "LYStackRouterDiscovery", package: "LYStackRouter")]
        ),
        .target(
            name: "DemoMessages",
            dependencies: ["DemoRoutes", .product(name: "LYStackRouterDiscovery", package: "LYStackRouter")]
        )
    ],
    swiftLanguageModes: [.v6]
)
