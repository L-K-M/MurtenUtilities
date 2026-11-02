import Foundation

/// A temporary folder removed when the test ends, so file tests never touch
/// the user's data.
final class ScratchDirectory {
    let url: URL

    init(_ name: String = "scratch") {
        url = FileManager.default.temporaryDirectory
            .appendingPathComponent("obtainintosh-tests-\(name)-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    }

    deinit {
        try? FileManager.default.removeItem(at: url)
    }

    func path(_ relative: String) -> URL {
        url.appendingPathComponent(relative)
    }

    /// Writes `bytes` at `relative`, creating folders.
    @discardableResult
    func write(_ bytes: [UInt8], to relative: String) -> URL {
        let file = path(relative)
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        _ = FileManager.default.createFile(atPath: file.path, contents: Data(bytes))
        return file
    }

    /// An application bundle with the given Info.plist keys.
    @discardableResult
    func bundle(_ relative: String, _ info: [String: Any]) -> URL {
        let bundle = path(relative)
        let contents = bundle.appendingPathComponent("Contents")
        try? FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        let data = try? PropertyListSerialization.data(fromPropertyList: info, format: .xml, options: 0)
        _ = FileManager.default.createFile(atPath: contents.appendingPathComponent("Info.plist").path, contents: data)
        return bundle
    }

    func mode(_ relative: String) -> Int? {
        let attributes = try? FileManager.default.attributesOfItem(atPath: path(relative).path)
        return (attributes?[.posixPermissions] as? NSNumber)?.intValue
    }

    func setMode(_ mode: Int, _ relative: String) {
        try? FileManager.default.setAttributes([.posixPermissions: NSNumber(value: mode)], ofItemAtPath: path(relative).path)
    }

    /// Files in the folder whose names start with `prefix` and end in `.tmp`.
    func temporaryFiles(of name: String) -> [String] {
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: url.path)) ?? []
        return entries.filter { $0.hasPrefix(name + ".") && $0.hasSuffix(".tmp") }.sorted()
    }
}
