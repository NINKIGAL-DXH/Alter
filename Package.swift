// swift-tools-version: 5.10
import PackageDescription
let package = Package(
    name: "Alter", platforms: [.macOS(.v14)],
    products: [.executable(name: "Alter", targets: ["AlterApp"]), .library(name: "AlterCore", targets: ["AlterCore"])],
    targets: [
        .target(name: "AlterCore"),
        .executableTarget(name: "AlterApp", dependencies: ["AlterCore"], resources: [.copy("Resources")]),
        .testTarget(name: "AlterCoreTests", dependencies: ["AlterCore"])
    ])
