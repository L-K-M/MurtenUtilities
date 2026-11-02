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
// Ported from an .xcodeproj (Swift 5 mode there too). RepoMenCore: scan, ageing,
// selection and reclaim verification, Foundation only. RepoMenModule: the pane,
// the privileged and tmutil runners, the watcher and auto-trash.
let repoMenTargets: [Target] = [
    .target(name: "RepoMenCore", dependencies: ["MurtenCore"]),
    .target(name: "RepoMenModule", dependencies: ["RepoMenCore", "MurtenCore", "MurtenModuleKit"]),
    .testTarget(name: "RepoMenCoreTests", dependencies: ["RepoMenCore", "MurtenCore"]),
    .testTarget(name: "RepoMenModuleTests",
                dependencies: ["RepoMenModule", "RepoMenCore", "MurtenCore", "MurtenModuleKit"])
]
let repoMenModule: [Target.Dependency] = ["RepoMenModule"]

// MARK: BootCaptain
let bootCaptainTargets: [Target] = []
let bootCaptainModule: [Target.Dependency] = []

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
