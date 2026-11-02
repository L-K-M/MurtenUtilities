import Foundation
import ObtainintoshCore

/// What a repository offers to download: the assets of a release or, for a
/// repository that publishes no releases, the fonts committed to it.
enum PublishedFiles {
    case release(ForgeRelease)
    case fonts(RepositoryFonts)

    /// The release to install from, with a released font's declared version.
    func release(filter: AssetFilter?, architecture: CPUArchitecture, transport: HTTPTransport,
                 authorization: @Sendable (String) -> String?) async throws -> Release {
        switch self {
        case .release(let forgeRelease):
            let release = try forgeRelease.buildRelease(filter: filter, architecture: architecture)
            return await Self.withDeclaredFontVersion(release, transport: transport, authorization: authorization)
        case .fonts(let fonts):
            let font = try fonts.pick(filter: filter, architecture: architecture)
            let version = try await RemoteFontReader.readVersion(url: font.browserDownloadURL, transport: transport,
                                                                 authorization: authorization(font.browserDownloadURL))
            return Release(version: version, downloadURL: font.browserDownloadURL, fileName: font.name,
                           fileSize: font.size)
        }
    }

    /// The programs on offer, and the one an entry without a filter gets.
    func programs(architecture: CPUArchitecture, transport: HTTPTransport,
                  authorization: @Sendable (String) -> String?) async throws -> ReleasePrograms {
        switch self {
        case .release(let release):
            return release.programs(architecture: architecture)
        case .fonts(let fonts):
            let font = try fonts.pick(filter: nil, architecture: architecture)
            let version = try await RemoteFontReader.readVersion(url: font.browserDownloadURL, transport: transport,
                                                                 authorization: authorization(font.browserDownloadURL))
            return ReleasePrograms(version: version, programs: fonts.names(architecture: architecture),
                                   defaultProgram: AssetFilter.programName(font.name))
        }
    }

    /// A font released as an asset takes the version it declares, which is
    /// what an installed copy is compared with: a tag such as `r2024-01` says
    /// nothing about it. When the font cannot be read, the tag stands.
    static func withDeclaredFontVersion(_ release: Release, transport: HTTPTransport,
                                        authorization: @Sendable (String) -> String?) async -> Release {
        guard FontFile.isFontFile(release.fileName) else { return release }
        var declared = release
        if let version = try? await RemoteFontReader.readVersion(url: release.downloadURL, transport: transport,
                                                                 authorization: authorization(release.downloadURL)) {
            declared.version = version
        }
        return declared
    }
}
