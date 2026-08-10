// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "Vaakya",
    platforms: [
        .macOS(.v14)
    ],
    products: [
        .library(name: "VaakyaCore", targets: ["VaakyaCore"]),
        .executable(name: "Vaakya", targets: ["Vaakya"]),
    ],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.15.5"),
    ],
    targets: [
        .target(
            name: "VaakyaCore",
            path: "Sources/VaakyaWorkSafeCore"
        ),
        .executableTarget(
            name: "Vaakya",
            dependencies: [
                "VaakyaCore",
                .product(name: "FluidAudio", package: "FluidAudio"),
            ],
            path: "Sources/VaakyaWorkSafe"
        ),
        .testTarget(
            name: "VaakyaWorkSafeTests",
            dependencies: ["VaakyaCore"],
            path: "Tests/VaakyaWorkSafeTests"
        ),
    ]
)
