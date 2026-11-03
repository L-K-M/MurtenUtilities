import XCTest
@testable import ShortkingKit

/// The helper lookup the suite relies on: the bundled name inside the app, the
/// SwiftPM product name in the build directory.
final class ProbeRunnerLocationTests: XCTestCase {

    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ProbeRunnerLocationTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private var names: [String] { [ProbeRunner.helperName, ProbeRunner.buildProductName] }

    @discardableResult
    private func makeFile(_ name: String, executable: Bool) throws -> URL {
        let url = directory.appendingPathComponent(name)
        try Data("#!/bin/sh\n".utf8).write(to: url)
        try FileManager.default.setAttributes(
            [.posixPermissions: executable ? 0o755 : 0o644],
            ofItemAtPath: url.path
        )
        return url
    }

    func testFindsTheBuildProductName() throws {
        let product = try makeFile(ProbeRunner.buildProductName, executable: true)
        XCTAssertEqual(ProbeRunner.firstExecutable(named: names, in: [directory])?.path, product.path)
    }

    func testPrefersTheBundledName() throws {
        let bundled = try makeFile(ProbeRunner.helperName, executable: true)
        try makeFile(ProbeRunner.buildProductName, executable: true)
        XCTAssertEqual(ProbeRunner.firstExecutable(named: names, in: [directory])?.path, bundled.path)
    }

    func testIgnoresFilesThatCannotRun() throws {
        try makeFile(ProbeRunner.buildProductName, executable: false)
        XCTAssertNil(ProbeRunner.firstExecutable(named: names, in: [directory]))
    }

    func testMissingHelperMakesProbingUnavailable() {
        XCTAssertFalse(ProbeRunner(helperURL: nil).isAvailable)
    }

    /// `swift test` loads this bundle from the build directory, which is where
    /// SwiftPM also leaves the helper.
    func testSearchesBesideTheTestBundle() {
        let testBuildDirectory = Bundle(for: Self.self).bundleURL.deletingLastPathComponent()
        XCTAssertTrue(
            ProbeRunner.buildDirectories().contains { $0.standardizedFileURL == testBuildDirectory.standardizedFileURL }
        )
    }
}
