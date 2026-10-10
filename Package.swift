// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Classwise",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Classwise", targets: ["Classwise"]), .library(name: "BYEAPI", targets: ["BYEAPI"])],
    targets: [
        .target(name: "ClasswiseCore"),
        .target(name: "BYEAPI", dependencies: ["ClasswiseCore"], exclude: ["README.md"]),
        .executableTarget(name: "Classwise", dependencies: ["ClasswiseCore", "BYEAPI"], resources: [.process("Resources")]),
        .testTarget(name: "BYEAPITests", dependencies: ["BYEAPI", "ClasswiseCore"]),
        .testTarget(name: "ClasswiseCoreTests", dependencies: ["ClasswiseCore"], resources: [.process("Fixtures")]),
        .testTarget(name: "ClasswiseAppTests", dependencies: ["Classwise", "ClasswiseCore", "BYEAPI"])
    ]
)
