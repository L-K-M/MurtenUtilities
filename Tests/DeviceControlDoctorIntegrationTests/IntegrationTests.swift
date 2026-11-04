import XCTest
import DoctorCore
@testable import DeviceControlDoctorModule

final class IntegrationTests: XCTestCase {
    func testCommandRunnerDrainsOutputBeyondPipeCapacity() async {
        let output = String(repeating: "x", count: 150_000)
        let result = await ProcessRunner().run("/usr/bin/printf", ["%s", output])
        XCTAssertEqual(result.exitCode, 0)
        XCTAssertFalse(result.timedOut)
        XCTAssertEqual(result.output.count, 131_072)
        XCTAssertTrue(result.outputTruncated)
    }
    func testCommandTimeoutTerminatesOnlyItsChild() async {
        let started = Date()
        let result = await ProcessRunner().run("/bin/sleep", ["5"], timeout: 0.15)
        XCTAssertTrue(result.timedOut)
        XCTAssertLessThan(Date().timeIntervalSince(started), 3)
    }
    func testMissingExecutableIsAnErrorNotAPermissionDenial() async {
        let result = await ProcessRunner().run("/nonexistent/DeviceControlDoctorFixture", [])
        XCTAssertEqual(result.exitCode, -1)
        XCTAssertFalse(result.output.isEmpty)
    }
    func testCatalogReadsChangedInfoPlistWithoutBundleCache() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let app = root.appendingPathComponent("Example.app")
        let contents = app.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contents, withIntermediateDirectories: true)
        func write(_ version: String, _ identifier: String) throws {
            let data = try PropertyListSerialization.data(fromPropertyList: ["CFBundleIdentifier": identifier, "CFBundleName": "Example", "CFBundleShortVersionString": version], format: .xml, options: 0)
            try data.write(to: contents.appendingPathComponent("Info.plist"), options: .atomic)
        }
        try write("1", "com.example.One")
        XCTAssertEqual(AppCatalog.app(at: app)?.version, "1")
        try write("2", "com.example.Two")
        XCTAssertEqual(AppCatalog.app(at: app)?.version, "2")
        XCTAssertEqual(AppCatalog.app(at: app)?.bundleID, "com.example.Two")
    }
}
