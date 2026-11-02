import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif
import ObtainintoshCore

/// Downloads a release asset into the temporary cache, streaming to disk
/// with progress, and publishes it under its real name only once it is
/// complete and exactly the size the forge reported. It never opens,
/// installs or replaces anything.
public struct ReleaseDownloader: Sendable {
    /// How long a download may go without data before it is abandoned.
    /// There is deliberately no total timeout: a large asset on a slow link
    /// is fine.
    public static let idleTimeout: TimeInterval = 60
    /// Progress is reported about this often.
    static let progressStep: UInt64 = 256 * 1024

    /// `$TMPDIR/obtainintosh-downloads`, shared with the standalone app.
    public static var defaultCacheRoot: URL {
        FileManager.default.temporaryDirectory.appendingPathComponent(DownloadLayout.cacheDirectoryName,
                                                                      isDirectory: true)
    }

    private let transport: HTTPTransport
    private let cacheRoot: URL

    public init(transport: HTTPTransport, cacheRoot: URL = ReleaseDownloader.defaultCacheRoot) {
        self.transport = transport
        self.cacheRoot = cacheRoot
    }

    /// Downloads `release` for the program `appKey` and returns where the
    /// file landed. Cancelling the calling task cancels the download and
    /// removes the partial file.
    public func download(_ release: Release, auth: DownloadAuth?, appKey: String,
                         progress: @escaping @Sendable (UInt64, UInt64) -> Void) async throws -> URL {
        // Without a size the download cannot be validated, and an
        // unvalidated download is what puts a truncated file in front of the user.
        guard let expectedSize = release.fileSize else {
            throw ObtainintoshError("The release asset is missing its expected size")
        }
        guard let url = URL(string: release.downloadURL) else {
            throw ObtainintoshError("The release asset has an invalid address: \(release.downloadURL)")
        }

        var request = URLRequest(url: url, timeoutInterval: Self.idleTimeout)
        request.setValue(ObtainintoshUserAgent.value, forHTTPHeaderField: "User-Agent")
        // Private-instance assets need the lookup's credentials, and only
        // on the instance's own origin.
        if let header = auth?.authorizationHeader(for: release.downloadURL) {
            request.setValue(header, forHTTPHeaderField: "Authorization")
        }

        let response: HTTPStream
        do {
            response = try await transport.stream(request)
        } catch {
            throw Self.describe(error, phase: "Failed to start download")
        }
        var published = false
        defer {
            if !published { response.cancel() }
        }
        guard response.isSuccess else {
            throw ObtainintoshError("Download failed: server returned \(ForgeMessages.statusText(response.status))")
        }
        progress(0, expectedSize)

        try PrivateFile.prepareDirectory(cacheRoot)
        let layout = try DownloadLayout(root: cacheRoot, appKey: appKey, version: release.version,
                                        fileName: release.fileName)
        try PrivateFile.prepareDirectory(layout.directory)
        defer {
            if !published { Self.discardPartial(layout) }
        }

        guard FileManager.default.createFile(atPath: layout.partial.path, contents: nil) else {
            throw ObtainintoshError("Failed to create download file")
        }
        let handle: FileHandle
        do {
            handle = try FileHandle(forWritingTo: layout.partial)
        } catch {
            throw ObtainintoshError("Failed to open download file: \(error.localizedDescription)")
        }
        defer { try? handle.close() }

        var downloaded: UInt64 = 0
        var lastReported: UInt64 = 0
        do {
            for try await chunk in response.body {
                try handle.write(contentsOf: chunk)
                downloaded += UInt64(chunk.count)
                // Stop as soon as the response outgrows what the forge
                // advertised, rather than filling the disk.
                if downloaded > expectedSize {
                    throw ObtainintoshError("Download exceeded the reported asset size: received \(downloaded) "
                        + "bytes, expected \(expectedSize) bytes")
                }
                if downloaded - lastReported >= Self.progressStep {
                    progress(downloaded, expectedSize)
                    lastReported = downloaded
                }
            }
        } catch {
            throw Self.describe(error, phase: "Failed while downloading")
        }
        try Task.checkCancellation()

        try DownloadLayout.validateSize(downloaded, expected: expectedSize)
        do {
            try handle.synchronize()
        } catch {
            throw ObtainintoshError("Failed to sync download file: \(error.localizedDescription)")
        }

        // Only a whole, correctly sized file gets the real name; it replaces
        // an earlier download of the same version.
        guard rename(layout.partial.path, layout.completed.path) == 0 else {
            throw ObtainintoshError("Failed to publish completed download: \(String(cString: strerror(errno)))")
        }
        published = true
        progress(downloaded, expectedSize)
        return layout.completed
    }

    /// The partial file goes, and its folder when nothing else is in it: a
    /// completed file from an earlier download of the same version may sit
    /// there, and a failed re-download must not delete the good copy.
    static func discardPartial(_ layout: DownloadLayout) {
        unlink(layout.partial.path)
        rmdir(layout.directory.path)
    }

    private static func describe(_ error: Error, phase: String) -> Error {
        if error is CancellationError { return error }
        if let urlError = error as? URLError {
            switch urlError.code {
            case .cancelled: return CancellationError()
            case .timedOut:
                return ObtainintoshError("Download timed out after \(Int(idleTimeout)) seconds without receiving data")
            default: break
            }
        }
        if error is ObtainintoshError { return error }
        return ObtainintoshError("\(phase): \(error.localizedDescription)")
    }
}
