// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Shepit",
    platforms: [.macOS("14.2")],
    products: [
        .library(name: "ShepitCore", targets: ["ShepitCore"]),
        .library(name: "ShepitEngines", targets: ["ShepitEngines"]),
        .executable(name: "Shepit", targets: ["Shepit"])
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", exact: "1.1.1"),
        .package(url: "https://github.com/FluidInference/FluidAudio.git", exact: "0.17.7")
    ],
    targets: [
        .target(name: "ShepitCore"),
        .binaryTarget(name: "whisper", path: "Vendor/whisper.xcframework"),
        .target(
            name: "ShepitEngines",
            dependencies: ["ShepitCore", "whisper", .product(name: "WhisperKit", package: "WhisperKit"), .product(name: "FluidAudio", package: "FluidAudio")],
            linkerSettings: [.linkedFramework("Accelerate"), .linkedFramework("Metal"), .linkedFramework("Foundation")]
        ),
        .executableTarget(name: "Shepit", dependencies: ["ShepitCore", "ShepitEngines"]),
        .testTarget(name: "ShepitCoreTests", dependencies: ["ShepitCore"]),
        .testTarget(name: "ShepitEnginesTests", dependencies: ["ShepitEngines"], resources: [.copy("Fixtures")]),
        .testTarget(name: "ShepitTests", dependencies: ["Shepit", "ShepitCore"])
    ],
    swiftLanguageModes: [.v6]
)
