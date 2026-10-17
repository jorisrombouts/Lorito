// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "lorito",
    platforms: [.macOS("26.0")],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.17.7"),
    ],
    targets: [
        .executableTarget(
            name: "lorito",
            dependencies: [.product(name: "FluidAudio", package: "FluidAudio")]
        ),
    ]
)
