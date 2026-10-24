// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Classwise",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "BYERetirement", targets: ["BYERetirement"]), .executable(name: "Classwise", targets: ["Classwise"]), .library(name: "BYEAPI", targets: ["BYEAPI"])],
    dependencies: [.package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.0")],
    targets: [
        .executableTarget(name: "BYERetirement", dependencies: [.product(name: "Sparkle", package: "Sparkle")], linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
        .testTarget(name: "BYERetirementTests", dependencies: ["BYERetirement"]),
        .target(name: "ClasswiseCore"),
        .target(name: "BYEAPI", dependencies: ["ClasswiseCore"], exclude: ["README.md"]),
        .executableTarget(name: "Classwise", dependencies: ["ClasswiseCore", "BYEAPI", .product(name: "Sparkle", package: "Sparkle")], resources: [.process("Resources")],
                          // Packaged apps embed Sparkle.framework in Contents/Frameworks.
                          linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]),
        .testTarget(name: "BYEAPITests", dependencies: ["BYEAPI", "ClasswiseCore"]),
        .testTarget(name: "ClasswiseCoreTests", dependencies: ["ClasswiseCore"], exclude: ["Vectors"], resources: [.process("Fixtures")]),
        .testTarget(name: "ClasswiseAppTests", dependencies: ["Classwise", "ClasswiseCore", "BYEAPI"])
    ]
)
