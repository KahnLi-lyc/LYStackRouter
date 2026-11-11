// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "DemoCommunityFeature",
    platforms: [.iOS(.v16)],
    products: [.library(name: "DemoCommunityFeature", targets: ["DemoCommunityFeature"])],
    dependencies: [.package(name: "LYStackRouter", path: "../../.."), .package(path: "../DemoRouteContract"), .package(path: "../DemoUIKit")],
    targets: [
        .target(name: "DemoCommunityFeature", dependencies: [.product(name: "LYStackRouter", package: "LYStackRouter"), .product(name: "DemoRouteContract", package: "DemoRouteContract"), .product(name: "DemoUIKit", package: "DemoUIKit"), .product(name: "LYStackRouterDiscovery", package: "LYStackRouter")]),
        .testTarget(name: "DemoCommunityFeatureTests", dependencies: ["DemoCommunityFeature"])
    ],
    swiftLanguageModes: [.v6]
)
