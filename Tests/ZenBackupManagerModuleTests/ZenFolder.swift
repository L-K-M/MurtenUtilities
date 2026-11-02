import Foundation
import XCTest
@testable import ZenBackupManagerCore

extension XCTestCase {
    /// A fixture Zen folder, removed when the test ends.
    func makeZenFolder() throws -> ZenFolder {
        let zen = try ZenFolder()
        addTeardownBlock { try? FileManager.default.removeItem(at: zen.root) }
        return zen
    }
}

/// A temporary stand-in for ~/Library/Application Support/zen. Tests never
/// touch the real profiles.
final class ZenFolder: Sendable {
    let root: URL

    init() throws {
        root = FileManager.default.temporaryDirectory.resolvingSymlinksInPath()
            .appendingPathComponent("ZenFolder-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    var safetyRoot: URL { root.appendingPathComponent("Safety Copies") }

    /// Writes profiles.ini listing `names` (the first is the default) and a
    /// prefs.js in each profile folder.
    func list(_ names: [String]) throws {
        var ini = ""
        for (index, name) in names.enumerated() {
            try FileManager.default.createDirectory(at: directory(name), withIntermediateDirectories: true)
            try Data().write(to: directory(name).appendingPathComponent("prefs.js"))
            ini += "[Profile\(index)]\nName=\(name)\nPath=Profiles/\(name)\nIsRelative=1\n"
            if index == 0 { ini += "Default=1\n" }
        }
        try ini.write(to: root.appendingPathComponent("profiles.ini"), atomically: true, encoding: .utf8)
    }

    func directory(_ name: String) -> URL {
        root.appendingPathComponent("Profiles/\(name)")
    }

    /// The profile as discovery reports it, so ids match.
    func profile(_ name: String) throws -> ZenProfile {
        try XCTUnwrap(ProfileDiscovery.discover(root: root).first { $0.name == name })
    }

    /// Writes a readable session snapshot dated `daysAgo` before `now`.
    func snapshot(_ name: String, at relativePath: String, tabs: [String] = [], daysAgo: Double, now: Date = Date()) throws {
        let file = directory(name).appendingPathComponent(relativePath)
        try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        let entries = tabs.map { "{\"entries\":[{\"url\":\"\($0)\"}]}" }.joined(separator: ",")
        try Self.session("{\"tabs\":[\(entries)],\"spaces\":[]}").write(to: file)
        try FileManager.default.setAttributes([.modificationDate: now.addingTimeInterval(-daysAgo * 86_400)], ofItemAtPath: file.path)
    }

    /// A mozLz4 file holding `json` as one literal LZ4 block, so the tests
    /// need no encoder.
    static func session(_ json: String) -> Data {
        let body = Data(json.utf8)
        precondition((15..<270).contains(body.count), "one length byte covers 15...269 literals")
        var length = UInt32(body.count).littleEndian
        return MozillaLZ4.magic + withUnsafeBytes(of: &length) { Data($0) } + Data([0xf0, UInt8(body.count - 15)]) + body
    }
}
