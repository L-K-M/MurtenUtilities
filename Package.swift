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
let bootCaptainTargets: [Target] = []
let bootCaptainModule: [Target.Dependency] = []

// MARK: DeviceControlDoctor
let deviceControlDoctorTargets: [Target] = []
let deviceControlDoctorModule: [Target.Dependency] = []

// MARK: Shortking
// Moved from Shortking (docs/modules.md, Provenance). ShortkingCore is the pure
// model and conflict analysis split out of the source's ShortkingKit, which keeps
// the AppKit, Carbon, SkyLight and process side. ShortkingProbe is the
// short-lived probe helper; scripts/build-app.sh embeds it as
// Contents/MacOS/shortking-probe.
let shortkingTargets: [Target] = [
    .target(name: "ShortkingCore"),
    .target(name: "ShortkingKit", dependencies: ["ShortkingCore"]),
    .executableTarget(name: "ShortkingProbe", dependencies: ["ShortkingKit", "ShortkingCore"]),
    .testTarget(name: "ShortkingCoreTests", dependencies: ["ShortkingCore"]),
    .testTarget(name: "ShortkingKitTests", dependencies: ["ShortkingKit", "ShortkingCore"])
]
let shortkingModule: [Target.Dependency] = []

// MARK: HallPass
let hallPassTargets: [Target] = []
let hallPassModule: [Target.Dependency] = []

// MARK: ZenBackupManager
let zenBackupManagerTargets: [Target] = []
let zenBackupManagerModule: [Target.Dependency] = []

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
