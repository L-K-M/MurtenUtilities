import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import ObtainintoshCore
@testable import ObtainintoshServices

final class ReleaseDownloaderTests: XCTestCase {
    private final class ProgressLog: @unchecked Sendable {
        private let lock = NSLock()
        private var entries: [UInt64] = []
        func append(_ value: UInt64) { lock.withLock { entries.append(value) } }
        var values: [UInt64] { lock.withLock { entries } }
    }

    private func release(_ size: UInt64?, url: String = "https://github.com/o/r/releases/download/v1.0/App.dmg") -> Release {
        Release(version: "1.0", downloadURL: url, fileName: "App.dmg", fileSize: size)
    }

    private func chunks(_ total: Int, of size: Int = 100_000) -> [Data] {
        stride(from: 0, to: total, by: size).map { Data(repeating: 7, count: min(size, total - $0)) }
    }

    func testADownloadLandsUnderItsRealNameWithProgress() async throws {
        let cache = ScratchDirectory("download-ok")
        let total = 600_000
        let transport = FakeTransport([.chunks(200, chunks(total))])
        let log = ProgressLog()

        let file = try await ReleaseDownloader(transport: transport, cacheRoot: cache.url)
            .download(release(UInt64(total)), auth: nil, appKey: "app-1") { done, _ in log.append(done) }

        XCTAssertEqual(file.path, cache.path("app-1/1.0/App.dmg").path)
        XCTAssertEqual(try Data(contentsOf: file).count, total)
        XCTAssertFalse(FileManager.default.fileExists(atPath: cache.path("app-1/1.0/App.dmg.part").path))
        XCTAssertEqual(log.values.first, 0)
        XCTAssertEqual(log.values.last, UInt64(total))
        XCTAssertGreaterThan(log.values.count, 2)
        XCTAssertEqual(cache.mode("app-1/1.0"), 0o700)
        XCTAssertNil(transport.requests[0].authorization)
    }

    func testAShortDownloadIsRejectedAndCleanedUp() async throws {
        let cache = ScratchDirectory("download-short")
        let transport = FakeTransport([.chunks(200, chunks(900))])
        do {
            _ = try await ReleaseDownloader(transport: transport, cacheRoot: cache.url)
                .download(release(1000), auth: nil, appKey: "app-1") { _, _ in }
            XCTFail("accepted a short download")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("Downloaded 900 bytes"), error.localizedDescription)
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: cache.path("app-1/1.0").path), "empty folder survived")
    }

    func testADownloadThatOutgrowsItsSizeIsStopped() async {
        let cache = ScratchDirectory("download-long")
        let transport = FakeTransport([.chunks(200, chunks(5000, of: 1000))])
        do {
            _ = try await ReleaseDownloader(transport: transport, cacheRoot: cache.url)
                .download(release(2500), auth: nil, appKey: "app-1") { _, _ in }
            XCTFail("accepted an oversized download")
        } catch {
            XCTAssertTrue(error.localizedDescription.contains("exceeded the reported asset size"), error.localizedDescription)
        }
    }

    func testAFailedReDownloadKeepsTheEarlierCompletedFile() async throws {
        let cache = ScratchDirectory("download-redo")
        let earlier = cache.write(Array("the earlier good file".utf8), to: "app-1/1.0/App.dmg")
        let transport = FakeTransport([.chunks(200, chunks(10))])

        do {
            _ = try await ReleaseDownloader(transport: transport, cacheRoot: cache.url)
                .download(release(1000), auth: nil, appKey: "app-1") { _, _ in }
            XCTFail("accepted a short download")
        } catch {}

        XCTAssertEqual(try String(contentsOf: earlier, encoding: .utf8), "the earlier good file")
        XCTAssertFalse(FileManager.default.fileExists(atPath: cache.path("app-1/1.0/App.dmg.part").path))
    }

    func testServerErrorsAndMissingSizesAreReported() async {
        let cache = ScratchDirectory("download-errors")
        do {
            _ = try await ReleaseDownloader(transport: FakeTransport([.json(404, "{}")]), cacheRoot: cache.url)
                .download(release(10), auth: nil, appKey: "app-1") { _, _ in }
            XCTFail("downloaded a 404")
        } catch {
            XCTAssertEqual(error.localizedDescription, "Download failed: server returned 404 Not Found")
        }
        do {
            _ = try await ReleaseDownloader(transport: FakeTransport([]), cacheRoot: cache.url)
                .download(release(nil), auth: nil, appKey: "app-1") { _, _ in }
            XCTFail("downloaded without a size")
        } catch {
            XCTAssertEqual(error.localizedDescription, "The release asset is missing its expected size")
        }
    }

    func testCredentialsGoOnlyToTheInstance() async throws {
        let cache = ScratchDirectory("download-auth")
        let auth = DownloadAuth(credentials: ForgeCredentials(username: "alice", token: "key123"),
                                origin: "https://git.example.internal")
        let transport = FakeTransport([.chunks(200, chunks(10)), .chunks(200, chunks(10))])
        let downloader = ReleaseDownloader(transport: transport, cacheRoot: cache.url)

        _ = try await downloader.download(release(10, url: "https://git.example.internal/o/r/releases/download/v1/App.dmg"),
                                          auth: auth, appKey: "a") { _, _ in }
        _ = try await downloader.download(release(10, url: "https://cdn.example.com/App.dmg"), auth: auth,
                                          appKey: "b") { _, _ in }

        XCTAssertNotNil(transport.requests[0].authorization)
        XCTAssertNil(transport.requests[1].authorization)
    }

    func testACancelledDownloadLeavesNothingBehind() async throws {
        let cache = ScratchDirectory("download-cancel")
        let body = AsyncThrowingStream<Data, Error> { continuation in
            continuation.yield(Data(repeating: 1, count: 10))
            // Never finishes: the download waits for more data until cancelled.
        }
        let transport = StallingTransport(response: HTTPStream(status: 200, headers: [:], body: body))
        let downloader = ReleaseDownloader(transport: transport, cacheRoot: cache.url)

        let task = Task { try await downloader.download(release(1000), auth: nil, appKey: "app-1") { _, _ in } }
        try await Task.sleep(nanoseconds: 100_000_000)
        task.cancel()

        do {
            _ = try await task.value
            XCTFail("finished a cancelled download")
        } catch {
            XCTAssertTrue(error is CancellationError, "\(error)")
        }
        XCTAssertFalse(FileManager.default.fileExists(atPath: cache.path("app-1/1.0").path))
    }

    func testDownloadsAreSerialisedAndTheSlotIsReusable() throws {
        let slot = DownloadSlot()
        var first: DownloadSlot.Lease? = try slot.acquire("App One (app-1)")
        XCTAssertNotNil(first)

        // A different program is refused too: there is one progress panel.
        XCTAssertThrowsError(try slot.acquire("App Two (app-2)")) {
            XCTAssertEqual("\($0)", "A download for App One (app-1) is already in progress; wait for it to finish "
                + "before starting another")
        }

        first = nil
        XCTAssertNoThrow(try slot.acquire("App Two (app-2)"))
    }

    func testBoundedOperationsRespectTheLimitAndReturnInputOrder() async {
        let gauge = Gauge()
        let results = await boundedOrderedMap(Array(0..<20), limit: 4) { index -> Int in
            await gauge.enter()
            try? await Task.sleep(nanoseconds: 1_000_000)
            await gauge.leave()
            return index * 10
        }

        XCTAssertEqual(results, (0..<20).map { $0 * 10 })
        let peak = await gauge.peak
        XCTAssertLessThanOrEqual(peak, 4, "limit exceeded")
        XCTAssertGreaterThan(peak, 1, "never ran concurrently")
    }

    func testAFailingOperationKeepsItsInputSlot() async {
        let results = await boundedOrderedMap(Array(0..<4), limit: 2) { index -> Result<Int, ObtainintoshError> in
            index == 1 ? .failure(ObtainintoshError("task \(index) fails")) : .success(index)
        }
        XCTAssertEqual(results.count, 4)
        XCTAssertEqual(try? results[0].get(), 0)
        XCTAssertNil(try? results[1].get())
        XCTAssertEqual(try? results[2].get(), 2)
        XCTAssertEqual(try? results[3].get(), 3)
    }
}

private actor Gauge {
    private var current = 0
    private(set) var peak = 0

    func enter() {
        current += 1
        peak = max(peak, current)
    }

    func leave() {
        current -= 1
    }
}

/// Serves one stream that never ends.
private struct StallingTransport: HTTPTransport {
    let response: HTTPStream

    func stream(_ request: URLRequest) async throws -> HTTPStream { response }
}
