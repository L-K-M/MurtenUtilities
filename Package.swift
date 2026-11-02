// swift-tools-version: 6.2
import PackageDescription

// Layout (docs/architecture.md, Package layout):
//
//   MurtenCore       pure contracts: registry, findings, rules, ledger, routes,
//                    settings, scheduling. No AppKit, no spawning, no privilege.
//   MurtenModuleKit  the provider protocol every migrated module implements.
//   MurtenShell      the app: model, services, scenes, views. Testable library.
//   MurtenUtilities  the executable: @main plus the module catalog.
//   <Tool>…          one block per module below (docs/migrating-a-module.md).

// MARK: - Suite

let suiteTargets: [Target] = [
    .target(name: "MurtenCore"),
    .target(name: "MurtenModuleKit", dependencies: ["MurtenCore"]),
    .target(
        name: "MurtenShell",
        dependencies: ["MurtenCore", "MurtenModuleKit", .product(name: "RigiUI", package: "Rigi")]
    ),
    .testTarget(name: "MurtenCoreTests", dependencies: ["MurtenCore"]),
    .testTarget(name: "MurtenShellTests", dependencies: ["MurtenShell", "MurtenModuleKit", "MurtenCore"])
]

// MARK: - Modules
//
// Each module owns one block: its targets, and the module library the
// executable links. Separate blocks keep parallel migrations from
// conflicting.

// MARK: DockVac
// DockVac's own targets kept Swift 6 language mode; the fake daemon and SSH
// bridge its driver tests spawn live in Tests/DockVacDockerTests/Scripts.
let dockVacSwift6: [SwiftSetting] = [.swiftLanguageMode(.v6)]
let dockVacTargets: [Target] = [
    // MurtenCore only for the suggestion rule, which stays pure.
    .target(name: "DockVacCore", dependencies: ["MurtenCore"], swiftSettings: dockVacSwift6),
    .target(name: "DockVacDocker", dependencies: ["DockVacCore"], swiftSettings: dockVacSwift6),
    // The pane, the watcher and the provider; the standalone app's AppKit views.
    .target(
        name: "DockVacModule",
        dependencies: [
            "DockVacCore", "DockVacDocker", "MurtenCore", "MurtenModuleKit",
            .product(name: "RigiUI", package: "Rigi")
        ],
        resources: [.copy("Resources/DockVacIcon.png")], swiftSettings: dockVacSwift6),
    .testTarget(
        name: "DockVacCoreTests", dependencies: ["DockVacCore", "MurtenCore"],
        resources: [.copy("Fixtures")], swiftSettings: dockVacSwift6),
    .testTarget(
        name: "DockVacDockerTests", dependencies: ["DockVacDocker", "DockVacCore"],
        exclude: ["Scripts"], swiftSettings: dockVacSwift6),
    .testTarget(
        name: "DockVacModuleTests",
        dependencies: ["DockVacModule", "DockVacCore", "DockVacDocker", "MurtenCore", "MurtenModuleKit"],
        swiftSettings: dockVacSwift6)
]
let dockVacModule: [Target.Dependency] = ["DockVacModule"]

// MARK: RepoMen
let repoMenTargets: [Target] = []
let repoMenModule: [Target.Dependency] = []

// MARK: BootCaptain
// Core and Kit move in from BootCaptain's own package; Core adds the
// watcher's pure diff and rule (Watch/). The app target's sources become
// BootCaptainModule. The CLI and the root helper stay in the BootCaptain repo
// (docs/modules.md, BootCaptain).
let bootCaptainTargets: [Target] = [
    // MurtenCore for the watcher's rule, which stays pure and lives here.
    .target(name: "BootCaptainCore", dependencies: ["MurtenCore"]),
    .target(name: "BootCaptainKit", dependencies: ["BootCaptainCore"]),
    .target(
        name: "BootCaptainModule",
        dependencies: ["BootCaptainCore", "BootCaptainKit", "MurtenCore", "MurtenModuleKit"]
    ),
    .testTarget(name: "BootCaptainCoreTests", dependencies: ["BootCaptainCore"]),
    .testTarget(name: "BootCaptainKitTests", dependencies: ["BootCaptainKit", "BootCaptainCore"]),
    .testTarget(
        name: "BootCaptainModuleTests",
        dependencies: ["BootCaptainModule", "BootCaptainCore", "BootCaptainKit", "MurtenCore", "MurtenModuleKit"]
    )
]
let bootCaptainModule: [Target.Dependency] = ["BootCaptainModule"]

// MARK: DeviceControlDoctor
// DoctorCore keeps its upstream name; its directory carries the tool's
// prefix like the module's other targets.
let deviceControlDoctorTargets: [Target] = [
    .target(name: "DoctorCore", dependencies: ["MurtenCore"], path: "Sources/DeviceControlDoctorCore"),
    .target(name: "DeviceControlDoctorModule", dependencies: ["DoctorCore", "MurtenCore", "MurtenModuleKit"]),
    .testTarget(name: "DeviceControlDoctorCoreTests", dependencies: ["DoctorCore", "MurtenCore"]),
    .testTarget(name: "DeviceControlDoctorIntegrationTests", dependencies: ["DeviceControlDoctorModule", "DoctorCore"]),
    .testTarget(name: "DeviceControlDoctorModuleTests",
                dependencies: ["DeviceControlDoctorModule", "DoctorCore", "MurtenCore", "MurtenModuleKit"])
]
let deviceControlDoctorModule: [Target.Dependency] = ["DeviceControlDoctorModule"]

// MARK: Shortking
let shortkingTargets: [Target] = []
let shortkingModule: [Target.Dependency] = []

// MARK: HallPass
// The source package (tools 6.0, no explicit mode) builds in Swift 6.
let hallPassSwiftSettings: [SwiftSetting] = [.swiftLanguageMode(.v6)]
let hallPassTargets: [Target] = [
    .target(name: "HallPassCore", swiftSettings: hallPassSwiftSettings),
    .target(
        name: "HallPassModule",
        dependencies: ["HallPassCore", "MurtenCore", "MurtenModuleKit"],
        swiftSettings: hallPassSwiftSettings
    ),
    .testTarget(name: "HallPassCoreTests", dependencies: ["HallPassCore"], swiftSettings: hallPassSwiftSettings),
    .testTarget(
        name: "HallPassModuleTests",
        dependencies: ["HallPassModule", "HallPassCore", "MurtenCore", "MurtenModuleKit"],
        swiftSettings: hallPassSwiftSettings
    )
]
let hallPassModule: [Target.Dependency] = ["HallPassModule"]

// MARK: ZenBackupManager
// Ported from the standalone app's .xcodeproj (Swift 5, the package default).
let zenBackupManagerTargets: [Target] = [
    .target(name: "ZenBackupManagerCore", dependencies: ["MurtenCore"]),
    .target(
        name: "ZenBackupManagerModule",
        dependencies: ["ZenBackupManagerCore", "MurtenCore", "MurtenModuleKit"]
    ),
    .testTarget(name: "ZenBackupManagerCoreTests", dependencies: ["ZenBackupManagerCore", "MurtenCore"]),
    .testTarget(
        name: "ZenBackupManagerModuleTests",
        dependencies: ["ZenBackupManagerModule", "ZenBackupManagerCore", "MurtenCore", "MurtenModuleKit"]
    )
]
let zenBackupManagerModule: [Target.Dependency] = ["ZenBackupManagerModule"]

// MARK: Obtainintosh
// A native port of the Tauri app (docs/modules.md, Obtainintosh).
let obtainintoshTargets: [Target] = [
    .target(name: "ObtainintoshCore", dependencies: ["MurtenCore"]),
    .target(name: "ObtainintoshServices", dependencies: ["ObtainintoshCore", "MurtenCore"]),
    .target(
        name: "ObtainintoshModule",
        dependencies: ["ObtainintoshCore", "ObtainintoshServices", "MurtenCore", "MurtenModuleKit"]
    ),
    .testTarget(
        name: "ObtainintoshCoreTests",
        dependencies: ["ObtainintoshCore", "MurtenCore"],
        resources: [.copy("Fixtures")]
    ),
    .testTarget(
        name: "ObtainintoshServicesTests",
        dependencies: ["ObtainintoshServices", "ObtainintoshCore", "MurtenCore"]
    ),
    .testTarget(
        name: "ObtainintoshModuleTests",
        dependencies: ["ObtainintoshModule", "ObtainintoshServices", "ObtainintoshCore", "MurtenCore",
                       "MurtenModuleKit"]
    )
]
let obtainintoshModule: [Target.Dependency] = ["ObtainintoshModule"]

// MARK: RunningMan
let runningManTargets: [Target] = []
let runningManModule: [Target.Dependency] = []

// MARK: Coreography
// The engine moved as SwiftPM targets (Coreography@f9820e6). Its sources
// are Swift 6, so every Coreography target keeps that language mode.
// CSQLite became CoreographySQLite: target names are package-wide.
let coreographySwift6: [SwiftSetting] = [.swiftLanguageMode(.v6)]
let coreographyTargets: [Target] = [
    .target(name: "CoreographySystem", linkerSettings: [
        .linkedFramework("IOKit", .when(platforms: [.macOS]))
    ]),
    .systemLibrary(name: "CoreographySQLite", path: "Sources/CoreographySQLite"),
    .target(
        name: "CoreographyDrivers",
        dependencies: [.target(name: "CoreographySystem", condition: .when(platforms: [.macOS])), "CoreographySQLite"],
        swiftSettings: coreographySwift6
    ),
    .target(name: "CoreographyKit", dependencies: ["CoreographyDrivers"], swiftSettings: coreographySwift6),
    .target(name: "CoreographyServices", dependencies: ["CoreographyKit"], swiftSettings: coreographySwift6),
    // The suite-facing core: the watcher's observation-only interface,
    // its CPU and pressure bookkeeping, and the pure suggestion rule.
    .target(name: "CoreographyCore", dependencies: ["MurtenCore"], swiftSettings: coreographySwift6),
    .testTarget(name: "CoreographyCoreTests", dependencies: ["CoreographyCore", "MurtenCore"],
                swiftSettings: coreographySwift6),
    // The Xcode app shell's views plus the provider, session and live
    // watcher reads: the pane, the menu section and Settings.
    .target(
        name: "CoreographyModule",
        dependencies: ["MurtenCore", "MurtenModuleKit", "CoreographyCore", "CoreographyServices",
                       "CoreographyKit", "CoreographyDrivers"],
        swiftSettings: coreographySwift6
    ),
    .testTarget(
        name: "CoreographyKitTests",
        dependencies: ["CoreographyKit", "CoreographyDrivers"],
        swiftSettings: coreographySwift6
    ),
    .testTarget(
        name: "CoreographyServicesTests",
        dependencies: ["CoreographyServices", "CoreographyKit", "CoreographyDrivers"],
        swiftSettings: coreographySwift6
    ),
    .testTarget(
        name: "CoreographyModuleTests",
        dependencies: ["CoreographyModule", "CoreographyCore", "MurtenCore", "MurtenModuleKit"],
        swiftSettings: coreographySwift6
    )
]
let coreographyModule: [Target.Dependency] = ["CoreographyModule"]

// MARK: - Assembly

let moduleTargets: [Target] = dockVacTargets + repoMenTargets + bootCaptainTargets
    + deviceControlDoctorTargets + shortkingTargets + hallPassTargets + zenBackupManagerTargets
    + obtainintoshTargets + runningManTargets + coreographyTargets

let moduleLibraries: [Target.Dependency] = dockVacModule + repoMenModule + bootCaptainModule
    + deviceControlDoctorModule + shortkingModule + hallPassModule + zenBackupManagerModule
    + obtainintoshModule + runningManModule + coreographyModule

let package = Package(
    name: "MurtenUtilities",
    platforms: [.macOS(.v26)],
    products: [.executable(name: "MurtenUtilities", targets: ["MurtenUtilities"])],
    dependencies: [
        // Rigi has no release tags yet; pin the immutable commit instead of a
        // moving branch. Bump deliberately and run the app + gallery first.
        .package(url: "https://github.com/L-K-M/Rigi.git", revision: "dcfc91e3b72aee612b2b48aed4a744397b78dc77")
    ],
    targets: suiteTargets + moduleTargets + [
        .executableTarget(
            name: "MurtenUtilities",
            dependencies: ["MurtenShell", "MurtenModuleKit"] + moduleLibraries
        )
    ],
    swiftLanguageModes: [.v5]
)
