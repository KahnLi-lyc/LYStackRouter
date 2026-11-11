// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "DemoUIKit",
    platforms: [.iOS(.v16)],
    products: [.library(name: "DemoUIKit", targets: ["DemoUIKit"])],
    dependencies: [.package(name: "LYStackRouter", path: "../../.."), .package(path: "../DemoRouteContract")],
    targets: [
        .target(name: "DemoUIKit", dependencies: [.product(name: "LYStackRouter", package: "LYStackRouter"), .product(name: "DemoRouteContract", package: "DemoRouteContract")])
    ],
    swiftLanguageModes: [.v6]
)
