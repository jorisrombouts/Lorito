// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Lorito",
    platforms: [.macOS("26.0")],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.17.7"),
    ],
    targets: [
        .executableTarget(
            name: "Lorito",
            dependencies: [.product(name: "FluidAudio", package: "FluidAudio")]
        ),
    ]
)
