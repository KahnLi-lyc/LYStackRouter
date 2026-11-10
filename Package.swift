// swift-tools-version: 6.1
import CompilerPluginSupport
import PackageDescription

let package = Package(
    name: "LYStackRouter",
    platforms: [
        .iOS(.v16),
        .macOS(.v13)
    ],
    products: [
        // 核心与 UIKit 执行引擎；不依赖任何第三方库。
        .library(name: "LYStackRouter", targets: ["LYStackRouter"]),
        // 可选：@LYRouteModule 宏与 Mach-O section 自动发现，需要 Swift 6.3 及以上工具链。
        .library(name: "LYStackRouterDiscovery", targets: ["LYStackRouterDiscovery"])
    ],
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax.git", "601.0.1" ..< "605.0.0")
    ],
    targets: [
        .target(name: "LYStackRouterCore"),
        .target(name: "LYStackRouter", dependencies: ["LYStackRouterCore"]),
        .macro(
            name: "LYStackRouterMacros",
            dependencies: [
                .product(name: "SwiftSyntax", package: "swift-syntax"),
                .product(name: "SwiftSyntaxBuilder", package: "swift-syntax"),
                .product(name: "SwiftSyntaxMacros", package: "swift-syntax"),
                .product(name: "SwiftDiagnostics", package: "swift-syntax"),
                .product(name: "SwiftCompilerPlugin", package: "swift-syntax")
            ]
        ),
        .target(name: "LYStackRouterDiscovery", dependencies: ["LYStackRouter", "LYStackRouterMacros"]),
        .testTarget(name: "LYStackRouterCoreTests", dependencies: ["LYStackRouterCore"]),
        .testTarget(name: "LYStackRouterTests", dependencies: ["LYStackRouter"]),
        .testTarget(
            name: "LYStackRouterMacrosTests",
            dependencies: [
                "LYStackRouterMacros",
                .product(name: "SwiftSyntaxMacrosTestSupport", package: "swift-syntax")
            ]
        ),
        .testTarget(name: "LYStackRouterDiscoveryTests", dependencies: ["LYStackRouterDiscovery"])
    ],
    swiftLanguageModes: [.v6]
)
