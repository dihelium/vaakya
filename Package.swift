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
        .executable(name: "vaakya-eval", targets: ["vaakya-eval"]),
    ],
    dependencies: [
        .package(url: "https://github.com/FluidInference/FluidAudio.git", from: "0.15.5"),
        .package(url: "https://github.com/groue/GRDB.swift.git", from: "7.11.1"),
    ],
    targets: [
        // Pure, testable logic. No AppKit, no networking (privacy invariant §2.1).
        // Lens HTTP clients live in the Vaakya app target, not here.
        .target(
            name: "VaakyaCore",
            dependencies: [
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            // The app bundler copies these files into Contents/Resources.
            // Keeping them out of SwiftPM resource bundles prevents its generated
            // development fallback from embedding the build machine's path.
            exclude: ["Resources"]
        ),
        // Menu-bar app shell: AppKit/SwiftUI, AV, AX, FluidAudio ASR.
        // Optional lens egress (URLSession) is gated by config + explicit consent.
        .executableTarget(
            name: "Vaakya",
            dependencies: [
                "VaakyaCore",
                .product(name: "FluidAudio", package: "FluidAudio"),
            ]
        ),
        // Offline evaluation harness (fixtures → TER + latency reports).
        .executableTarget(
            name: "vaakya-eval",
            dependencies: ["VaakyaCore"]
        ),
        .testTarget(
            name: "VaakyaCoreTests",
            dependencies: ["VaakyaCore", "Vaakya"]
        ),
    ]
)
