import Foundation

/// Picks the release asset this Mac can install. The standalone app also has
/// a Linux picker; the suite is macOS-only, so only the macOS one moved.
public enum AssetPicker {
    /// CPU families no supported Mac runs, spelled the ways release assets
    /// name them (Debian names like `ppc64el` and `armel` included: the
    /// boundary check means `ppc64` does not match inside `ppc64el`). Bare
    /// `x86` is absent on purpose: `_` and `-` are marker boundaries, so it
    /// would also match inside `x86_64` and reject every 64-bit Intel asset.
    public static let unsupportedCPUMarkers: Set<String> = [
        "armv5", "armv6", "armv7", "armel", "armhf", "i386", "i486", "i586", "i686", "i786", "x86_32",
        "x86-32",
        // 32-bit x86 by long-standing convention, like the win32/linux32 pairing.
        "linux32",
        "powerpc", "ppc", "ppc64", "ppc64el", "ppc64le", "mips", "mipsel", "mips64", "mips64el", "s390x",
        "sparc", "sparc64", "riscv32", "riscv64", "loongarch64", "loong64",
    ]

    private static let packageExtensions = [".dmg", ".pkg", ".app.tar.gz", ".tar.gz", ".zip"]
    /// The first index that is a generic archive rather than a macOS package.
    private static let firstGenericArchiveRank = 3
    private static let macOSMarkers = ["mac", "macos", "macosx", "darwin", "osx"]
    private static let otherOSMarkers = [
        "windows", "win", "win32", "win64", "linux", "linux32", "linux64", "ubuntu", "debian", "android",
        "freebsd", "openbsd", "netbsd", "solaris", "ios", "tvos",
    ]
    /// Separate markers because the boundary check intentionally does not
    /// match "universal" within "universal2".
    private static let universalMarkers = ["universal", "universal2"]
    private static let arm64Markers = ["arm64", "aarch64"]
    private static let intel64Markers = ["x86_64", "x86-64", "amd64", "x64", "intel"]
    /// An Intel-only asset on Apple Silicon: usable only through Rosetta 2.
    static let rosettaRank = 3

    public struct Rank: Comparable, Sendable {
        let architecture: Int
        let package: Int

        public static func < (lhs: Rank, rhs: Rank) -> Bool {
            (lhs.architecture, lhs.package) < (rhs.architecture, rhs.package)
        }
    }

    /// The asset this Mac can install, if any. A filter narrows the
    /// candidates to one program before ranking, so its platform preferences
    /// still apply within that program.
    public static func compatibleAsset<Asset: NamedAsset>(_ assets: [Asset], filter: AssetFilter?,
                                                          architecture: CPUArchitecture = .current) -> Asset? {
        let candidates = assets.filter { asset in filter.map { $0.matches(asset.name) } ?? true }
        return macOSAsset(candidates, architecture: architecture)
    }

    /// Ranks by (architecture, package format) with the asset name as the
    /// tiebreaker; nil when no asset suits the Mac.
    public static func macOSAsset<Asset: NamedAsset>(_ assets: [Asset], architecture: CPUArchitecture) -> Asset? {
        var best: (asset: Asset, rank: Rank)?
        for asset in assets {
            guard let rank = rank(of: asset.name, architecture: architecture) else { continue }
            guard let current = best else {
                best = (asset, rank)
                continue
            }
            if rank < current.rank
                || (rank == current.rank && asset.name.utf8.lexicographicallyPrecedes(current.asset.name.utf8)) {
                best = (asset, rank)
            }
        }
        return best?.asset
    }

    /// Where an asset name ranks for this Mac, or nil when it does not suit it.
    static func rank(of assetName: String, architecture: CPUArchitecture) -> Rank? {
        let name = assetName.asciiLowercased()
        guard let packageRank = packageFormatRank(name) else { return nil }
        if otherOSMarkers.contains(where: { hasNameMarker(name, $0) }) { return nil }

        let hasMacOSMarker = macOSMarkers.contains { hasNameMarker(name, $0) }
        let genericArchive = (firstGenericArchiveRank..<packageExtensions.count).contains(packageRank)
        if genericArchive && !hasMacOSMarker { return nil }

        let universal = universalMarkers.contains { hasNameMarker(name, $0) }
        let arm64 = arm64Markers.contains { hasNameMarker(name, $0) }
        let intel64 = intel64Markers.contains { hasNameMarker(name, $0) }
        let unsupportedCPU = unsupportedCPUMarkers.contains { hasNameMarker(name, $0) }

        if unsupportedCPU || (architecture == .x86_64 && arm64 && !intel64 && !universal) { return nil }

        // Intel-only builds stay a last resort on Apple Silicon because
        // Rosetta 2 can run them. The reverse is not possible.
        let architectureRank: Int
        switch architecture {
        case .arm64:
            if universal { architectureRank = 0 }
            else if arm64 { architectureRank = 1 }
            else if !intel64 { architectureRank = 2 }
            else { architectureRank = rosettaRank }
        case .x86_64:
            if universal { architectureRank = 0 }
            else if intel64 { architectureRank = 1 }
            else { architectureRank = 2 }
        }
        return Rank(architecture: architectureRank, package: packageRank)
    }

    /// Where a lowercased name ranks among the package formats, or nil when
    /// it is none of them. Fonts rank after every package, so a release that
    /// ships a program besides its font is tracked for the program. Fonts
    /// suit every system, so they need no platform marker.
    static func packageFormatRank(_ name: String) -> Int? {
        (packageExtensions + FontFile.extensions).firstIndex { name.hasSuffix($0) }
    }

    /// Whether `marker` occurs in `name` as a whole word: not preceded or
    /// followed by an ASCII letter or digit. Occurrences are scanned without
    /// overlap, like Rust's `match_indices`.
    static func hasNameMarker(_ name: String, _ marker: String) -> Bool {
        let haystack = Array(name.utf8)
        let needle = Array(marker.utf8)
        guard !needle.isEmpty, needle.count <= haystack.count else { return false }

        func isASCIIAlphanumeric(_ byte: UInt8) -> Bool {
            (byte >= 0x30 && byte <= 0x39) || (byte >= 0x41 && byte <= 0x5A) || (byte >= 0x61 && byte <= 0x7A)
        }

        var start = 0
        while start + needle.count <= haystack.count {
            guard haystack[start..<start + needle.count].elementsEqual(needle) else {
                start += 1
                continue
            }
            let end = start + needle.count
            let beforeOK = start == 0 || !isASCIIAlphanumeric(haystack[start - 1])
            let afterOK = end == haystack.count || !isASCIIAlphanumeric(haystack[end])
            if beforeOK && afterOK { return true }
            start = end
        }
        return false
    }
}
