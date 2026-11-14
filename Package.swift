// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MacProject",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "MacProject", targets: ["MacProject"]),
        .library(name: "ProjectCore", targets: ["ProjectCore"]),
    ],
    targets: [
        .target(name: "ProjectCore"),
        .executableTarget(name: "MacProject", dependencies: ["ProjectCore"]),
        .testTarget(name: "ProjectCoreTests", dependencies: ["ProjectCore"]),
    ]
)
