// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MurtenUtilities",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "MurtenUtilities", targets: ["MurtenUtilities"])],
    dependencies: [
        // Rigi has no release tags yet; pin the immutable commit instead of a
        // moving branch. Bump deliberately and run the app + gallery first.
        .package(url: "https://github.com/L-K-M/Rigi.git", revision: "dcfc91e3b72aee612b2b48aed4a744397b78dc77")
    ],
    targets: [
        .target(name: "MurtenCore"),
        .executableTarget(
            name: "MurtenUtilities",
            dependencies: ["MurtenCore", .product(name: "RigiUI", package: "Rigi")]
        ),
        .testTarget(name: "MurtenCoreTests", dependencies: ["MurtenCore"])
    ],
    swiftLanguageModes: [.v5]
)
