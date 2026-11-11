// swift-tools-version: 6.1
import PackageDescription

let package = Package(
    name: "DemoRouteContract",
    platforms: [.iOS(.v16)],
    products: [.library(name: "DemoRouteContract", targets: ["DemoRouteContract"])],
    // 契约只用到 Core 类型（LYRoutable、LYRoutePlacement）；Core 未单独作为产品发布，因此依赖 LYStackRouter 产品。
    dependencies: [.package(name: "LYStackRouter", path: "../../..")],
    targets: [
        .target(name: "DemoRouteContract", dependencies: [.product(name: "LYStackRouter", package: "LYStackRouter")])
    ],
    swiftLanguageModes: [.v6]
)
