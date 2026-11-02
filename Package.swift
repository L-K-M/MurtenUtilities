// swift-tools-version: 6.2
import PackageDescription

// Layout (docs/architecture.md, Package layout):
//
//   MurtenCore       pure contracts: registry, findings, rules, ledger, routes,
//                    settings, scheduling. No AppKit, no spawning, no privilege.
//   MurtenModuleKit  the provider protocol every migrated module implements.
//   MurtenShell      the app: model, services, scenes, views. Testable library.
//   MurtenUtilities  the executable: @main plus the module catalog.
let package = Package(
    name: "MurtenUtilities",
    platforms: [.macOS(.v26)],
    products: [.executable(name: "MurtenUtilities", targets: ["MurtenUtilities"])],
    dependencies: [
        // Rigi has no release tags yet; pin the immutable commit instead of a
        // moving branch. Bump deliberately and run the app + gallery first.
        .package(url: "https://github.com/L-K-M/Rigi.git", revision: "dcfc91e3b72aee612b2b48aed4a744397b78dc77")
    ],
    targets: [
        .target(name: "MurtenCore"),
        .target(name: "MurtenModuleKit", dependencies: ["MurtenCore"]),
        .target(
            name: "MurtenShell",
            dependencies: ["MurtenCore", "MurtenModuleKit", .product(name: "RigiUI", package: "Rigi")]
        ),
        .executableTarget(
            name: "MurtenUtilities",
            dependencies: ["MurtenShell", "MurtenModuleKit"]
        ),
        .testTarget(name: "MurtenCoreTests", dependencies: ["MurtenCore"]),
        .testTarget(name: "MurtenShellTests", dependencies: ["MurtenShell", "MurtenModuleKit", "MurtenCore"])
    ],
    swiftLanguageModes: [.v5]
)
