import Foundation

/// A release as both supported forges report it. Forgejo's API is
/// Gitea-compatible and names these fields exactly like GitHub's, so one type
/// decodes both and the asset picker stays shared. Fields the two disagree on
/// are ignored.
public struct ForgeRelease: Decodable, Equatable, Sendable {
    public var tagName: String
    public var body: String?
    public var assets: [ReleaseAsset]
    public var draft: Bool
    public var prerelease: Bool

    public init(tagName: String, body: String? = nil, assets: [ReleaseAsset], draft: Bool = false,
                prerelease: Bool = false) {
        self.tagName = tagName
        self.body = body
        self.assets = assets
        self.draft = draft
        self.prerelease = prerelease
    }

    private enum CodingKeys: String, CodingKey {
        case tagName = "tag_name"
        case body, assets, draft, prerelease
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        tagName = try container.decode(String.self, forKey: .tagName)
        body = try container.decodeIfPresent(String.self, forKey: .body)
        assets = try container.decode([ReleaseAsset].self, forKey: .assets)
        draft = try container.decodeIfPresent(Bool.self, forKey: .draft) ?? false
        prerelease = try container.decodeIfPresent(Bool.self, forKey: .prerelease) ?? false
    }

    // MARK: - Assets

    /// Turns the forge's release into ours, picking the asset this Mac can
    /// use, of the filtered program when there is a filter.
    public func buildRelease(filter: AssetFilter?, architecture: CPUArchitecture = .current) throws -> Release {
        guard let asset = AssetPicker.compatibleAsset(assets, filter: filter, architecture: architecture) else {
            throw ObtainintoshError("Selected release has no \(ReleaseSelection.platformLabel)-compatible asset")
        }
        return Release(version: ReleaseSelection.cleanVersionTag(tagName), downloadURL: asset.browserDownloadURL,
                       fileName: asset.name, fileSize: asset.size, releaseNotes: body)
    }

    public func hasCompatibleAsset(filter: AssetFilter?, architecture: CPUArchitecture = .current) -> Bool {
        AssetPicker.compatibleAsset(assets, filter: filter, architecture: architecture) != nil
    }

    /// The programs this release offers this Mac, and the one an entry
    /// without a filter gets.
    public func programs(architecture: CPUArchitecture = .current) -> ReleasePrograms {
        let defaultAsset = AssetPicker.compatibleAsset(assets, filter: nil, architecture: architecture)
        return ReleasePrograms(version: ReleaseSelection.cleanVersionTag(tagName),
                               programs: platformPrograms(architecture: architecture),
                               defaultProgram: defaultAsset.flatMap { AssetFilter.programName($0.name) })
    }

    /// The names of the programs with an asset this Mac can install, sorted:
    /// `["planchette", "poltergeist", "seance"]`.
    public func platformPrograms(architecture: CPUArchitecture = .current) -> [String] {
        ReleaseSelection.sortedProgramNames(assets).filter { name in
            hasCompatibleAsset(filter: .program(name), architecture: architecture)
        }
    }
}
