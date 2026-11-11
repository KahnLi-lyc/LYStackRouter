// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "DemoMessagingFeature",
    platforms: [.iOS(.v16)],
    products: [.library(name: "DemoMessagingFeature", targets: ["DemoMessagingFeature"])],
    dependencies: [.package(name: "LYStackRouter", path: "../../.."), .package(path: "../DemoRouteContract"), .package(path: "../DemoUIKit")],
    targets: [
        .target(name: "DemoMessagingFeature", dependencies: [.product(name: "LYStackRouter", package: "LYStackRouter"), .product(name: "DemoRouteContract", package: "DemoRouteContract"), .product(name: "DemoUIKit", package: "DemoUIKit"), .product(name: "LYStackRouterDiscovery", package: "LYStackRouter")]),
        .testTarget(name: "DemoMessagingFeatureTests", dependencies: ["DemoMessagingFeature"])
    ],
    swiftLanguageModes: [.v6]
)
