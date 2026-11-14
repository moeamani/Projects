// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "Gantt",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Gantt", targets: ["Gantt"]),
        .library(name: "ProjectCore", targets: ["ProjectCore"]),
    ],
    targets: [
        .target(name: "ProjectCore"),
        .executableTarget(name: "Gantt", dependencies: ["ProjectCore"]),
        .testTarget(name: "ProjectCoreTests", dependencies: ["ProjectCore"]),
    ]
)
