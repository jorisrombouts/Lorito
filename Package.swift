// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Lorito",
    platforms: [.macOS("26.0")],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", .upToNextMinor(from: "0.17.7")),   // FluidAudio changes its API between minor versions
    ],
    targets: [
        .executableTarget(
            name: "Lorito",
            dependencies: [.product(name: "FluidAudio", package: "FluidAudio")]
        ),
    ]
)
