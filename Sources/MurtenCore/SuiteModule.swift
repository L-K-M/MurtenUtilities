import Foundation

/// A tool offered by the suite: a pane the user can open and, optionally, a
/// background `Watcher` that feeds the suggestion feed. Modules here are
/// descriptors only — their implementations migrate in one at a time
/// (see docs/modules.md).
public struct SuiteModule: Identifiable, Equatable, Sendable {
    public enum Status: String, Equatable, Sendable {
        /// Registry placeholder; the tool has not been migrated yet.
        case planned
        /// The pane exists; a watcher may or may not be wired.
        case available
    }

    public let id: String
    public let name: String
    /// One line, as on the home screen — the Norton-style label.
    public let summary: String
    /// SF Symbol shown until the module gets its real icon (see docs/ui-direction.md).
    public let systemImage: String
    public let status: Status
    /// The repository the implementation migrates from, when one exists.
    public let sourceRepository: String?

    public init(id: String, name: String, summary: String, systemImage: String,
                status: Status = .planned, sourceRepository: String? = nil) {
        self.id = id
        self.name = name
        self.summary = summary
        self.systemImage = systemImage
        self.status = status
        self.sourceRepository = sourceRepository
    }
}

public enum ModuleRegistry {
    /// The planned roster in home-screen order (see PLAN.md / docs/modules.md).
    public static let all: [SuiteModule] = [
        SuiteModule(
            id: "dockvac", name: "DockVac",
            summary: "Reclaim space held by Docker images, volumes and build cache.",
            systemImage: "shippingbox", sourceRepository: "DockVac"),
        SuiteModule(
            id: "repomen", name: "RepoMen",
            summary: "Hunt down build artifacts and caches that eat your disk.",
            systemImage: "externaldrive", sourceRepository: "RepoMen"),
        SuiteModule(
            id: "bootcaptain", name: "BootCaptain",
            summary: "Inventory startup items and investigate boot failures.",
            systemImage: "power", status: .available, sourceRepository: "BootCaptain"),
        SuiteModule(
            id: "devicecontroldoctor", name: "DeviceControlDoctor",
            summary: "Diagnose privacy permissions that look granted but fail.",
            systemImage: "cross.case", status: .available, sourceRepository: "DeviceControlDoctor"),
        SuiteModule(
            id: "shortking", name: "Shortking",
            summary: "Find out who owns — or stole — a keyboard shortcut.",
            systemImage: "keyboard", sourceRepository: "Shortking"),
        SuiteModule(
            id: "hallpass", name: "HallPass",
            summary: "Exempt trusted networks from local-network privacy prompts.",
            systemImage: "network", sourceRepository: "HallPass"),
        SuiteModule(
            id: "zenbackupmanager", name: "Zen Backup Manager",
            summary: "Browse and restore browser-session backups on a timeline.",
            systemImage: "clock.arrow.circlepath", sourceRepository: "ZenBackupManager"),
        SuiteModule(
            id: "obtainintosh", name: "Obtainintosh",
            summary: "Track updates for apps and fonts installed from releases.",
            systemImage: "arrow.down.circle", sourceRepository: "Obtainintosh"),
        SuiteModule(
            id: "runningman", name: "RunningMan",
            summary: "Keep self-hosted CI runners alive and signed in.",
            systemImage: "figure.run", sourceRepository: "RunningMan"),
        SuiteModule(
            id: "coreography", name: "Coreography",
            summary: "Watch CPU, memory, disk and network in real time.",
            systemImage: "waveform.path.ecg", sourceRepository: "Coreography"),
    ]
}
