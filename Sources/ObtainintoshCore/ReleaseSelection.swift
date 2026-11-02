import Foundation

/// Which release of a repository's recent list to install from, and how to
/// explain it when none qualifies.
public enum ReleaseSelection {
    /// The platform assets are picked for, as named in messages.
    public static let platformLabel = "macOS"
    /// How far back to look when the newest release carries nothing this Mac
    /// can install. Matches the page size both forges are asked for.
    public static let recentReleaseLimit = 10
    /// How many programs a message names before summarising the rest, so it
    /// fits the bounded check message.
    static let maximumListedPrograms = 5

    /// Whether the list contains even one published release. Drafts do not
    /// count: both forges hide them from anyone without write access.
    public static func hasPublishedRelease(_ releases: [ForgeRelease]) -> Bool {
        releases.contains { !$0.draft }
    }

    /// Picks a release this Mac can install out of the recent list.
    ///
    /// When `releases/latest` answered, the repository publishes a stable
    /// channel and that is what the user tracks, so the search stays on it:
    /// quietly moving them onto a prerelease would change their subscription
    /// without saying so. When it 404d there is no such expectation, and the
    /// newest published release of any channel with an installable asset
    /// wins.
    public static func selectRecentRelease(_ releases: [ForgeRelease], stableReleasePublished: Bool,
                                           filter: AssetFilter?,
                                           architecture: CPUArchitecture = .current) throws -> ForgeRelease {
        // "No compatible release" implies releases exist and merely missed
        // this platform; an unpublished repository is a different problem,
        // and an easy one to miss, because drafts show on the releases page
        // for the repository's maintainers.
        if !stableReleasePublished && !hasPublishedRelease(releases) {
            throw ObtainintoshError("No published releases found among the releases visible to this app. Draft "
                + "releases are invisible to anyone without write access, so a release stuck in draft — for "
                + "example by a failed release workflow — shows on the releases page for its maintainers while "
                + "remaining unpublished")
        }

        let channel: Bool? = stableReleasePublished ? false : nil
        if let release = findCompatibleRelease(releases, prerelease: channel, filter: filter,
                                               architecture: architecture) {
            return release
        }
        throw ObtainintoshError(noCompatibleReleaseMessage(releases, prerelease: channel, filter: filter,
                                                           architecture: architecture))
    }

    /// The newest published release with an asset this Mac can use,
    /// optionally restricted to one channel. Both forges list newest first.
    public static func findCompatibleRelease(_ releases: [ForgeRelease], prerelease: Bool?, filter: AssetFilter?,
                                             architecture: CPUArchitecture = .current) -> ForgeRelease? {
        releases.first { release in
            !release.draft && inChannel(release, prerelease)
                && release.hasCompatibleAsset(filter: filter, architecture: architecture)
        }
    }

    /// Why no release qualified. With a filter it names the program and
    /// lists what the newest release of the channel offers instead, so a
    /// misspelt program can be corrected from the message alone.
    static func noCompatibleReleaseMessage(_ releases: [ForgeRelease], prerelease: Bool?, filter: AssetFilter?,
                                           architecture: CPUArchitecture) -> String {
        let channel = prerelease == false ? "stable " : ""
        guard let filter else {
            return "No \(platformLabel)-compatible \(channel)release found in the \(recentReleaseLimit) most "
                + "recent releases"
        }

        var message = "No \(platformLabel)-compatible \(channel)release of \"\(filter.canonical)\" found in the "
            + "\(recentReleaseLimit) most recent releases"
        let newest = releases.first { !$0.draft && inChannel($0, prerelease) }
        let programs = newest?.platformPrograms(architecture: architecture) ?? []
        if !programs.isEmpty {
            message += ". The newest offers: " + listPrograms(programs)
        } else if newest != nil {
            // Tells "no build for this platform at all" apart from a misspelling.
            message += ". The newest offers nothing for \(platformLabel)"
        }
        return message
    }

    /// `a, b, c`, or past the limit, `a, b, c, d, e and 2 more`.
    public static func listPrograms(_ programs: [String]) -> String {
        let listed = programs.prefix(maximumListedPrograms).joined(separator: ", ")
        let remaining = programs.count - maximumListedPrograms
        return remaining > 0 ? "\(listed) and \(remaining) more" : listed
    }

    /// The distinct program names of some assets, sorted bytewise.
    static func sortedProgramNames(_ assets: [some NamedAsset]) -> [String] {
        Set(assets.compactMap { AssetFilter.programName($0.name) })
            .sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }
    }

    private static func inChannel(_ release: ForgeRelease, _ prerelease: Bool?) -> Bool {
        prerelease.map { release.prerelease == $0 } ?? true
    }

    /// Strips a single leading "v" from a version tag, but only when it
    /// prefixes a number ("v1.2.3" → "1.2.3", "version-2" stays).
    public static func cleanVersionTag(_ tag: String) -> String {
        let tag = tag.trimmingCharacters(in: .whitespacesAndNewlines)
        if let first = tag.first, first == "v" || first == "V", tag.dropFirst().first?.isASCIIDigit == true {
            return String(tag.dropFirst())
        }
        return tag
    }
}
