import Foundation

struct BackupRecord: Identifiable, Sendable {
    enum Kind: String, Sendable { case current = "Current state", automatic = "Automatic", legacy = "Legacy", safety = "Safety copy" }
    let file: URL
    let modifiedAt: Date
    let bytes: Int
    let kind: Kind
    let preview: SessionPreview?
    let digest: String?
    let problem: String?
    var id: String { file.path }
    var date: Date { preview?.collectedAt ?? modifiedAt }
    var canRestore: Bool { preview != nil && digest != nil && kind != .current }
}
