// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "DemoRouteContract",
    platforms: [.iOS(.v16)],
    products: [.library(name: "DemoRouteContract", targets: ["DemoRouteContract"])],
    dependencies: [.package(name: "LYStackRouter", path: "../../..")],
    targets: [
        .target(name: "DemoRouteContract", dependencies: [.product(name: "LYStackRouter", package: "LYStackRouter")])
    ],
    swiftLanguageModes: [.v6]
)
