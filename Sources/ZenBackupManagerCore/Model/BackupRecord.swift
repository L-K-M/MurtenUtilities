import Foundation

public struct BackupRecord: Identifiable, Sendable {
    public enum Kind: String, Sendable { case current = "Current state", automatic = "Automatic", legacy = "Legacy", safety = "Safety copy" }
    public let file: URL
    public let modifiedAt: Date
    public let bytes: Int
    public let kind: Kind
    public let preview: SessionPreview?
    public let digest: String?
    public let problem: String?
    public var id: String { file.path }
    public var date: Date { preview?.collectedAt ?? modifiedAt }
    public var canRestore: Bool { preview != nil && digest != nil && kind != .current }
}
