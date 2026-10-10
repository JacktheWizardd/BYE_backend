// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Classwise",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "Classwise", targets: ["Classwise"])],
    targets: [
        .target(name: "ClasswiseCore"),
        .executableTarget(name: "Classwise", dependencies: ["ClasswiseCore"], resources: [.process("Resources")]),
        .testTarget(name: "ClasswiseCoreTests", dependencies: ["ClasswiseCore"], resources: [.process("Fixtures")]),
        .testTarget(name: "ClasswiseAppTests", dependencies: ["Classwise", "ClasswiseCore"])
    ]
)
