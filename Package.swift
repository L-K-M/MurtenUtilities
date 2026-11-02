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
let dockVacTargets: [Target] = []
let dockVacModule: [Target.Dependency] = []

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
let hallPassTargets: [Target] = []
let hallPassModule: [Target.Dependency] = []

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
let obtainintoshTargets: [Target] = []
let obtainintoshModule: [Target.Dependency] = []

// MARK: RunningMan
let runningManTargets: [Target] = []
let runningManModule: [Target.Dependency] = []

// MARK: Coreography
let coreographyTargets: [Target] = []
let coreographyModule: [Target.Dependency] = []

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
