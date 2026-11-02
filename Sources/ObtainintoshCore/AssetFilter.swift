import Foundation

/// Which program of a release an entry tracks, for repositories that publish
/// several programs side by side:
///
/// ```
///   seance-macos-universal.zip      ─┐
///   seance_1.9.0-1_amd64.deb         ├─ program "seance"
///   seance-linux-x64.AppImage       ─┘
///   seance-sync-linux-x64.tar.gz    ── program "seance-sync"
///   planchette-macos-universal.zip  ── program "planchette"
/// ```
///
/// A filter narrows the assets the platform picker ranks to one program, so
/// the picker's platform and architecture preferences still apply within it.
/// It is either a program name, compared with each asset's program name, or
/// a wildcard pattern over the whole file name for naming schemes program
/// names cannot tell apart (`*-gtk4-*`).
public enum AssetFilter: Equatable, Hashable, Sendable {
    /// Assets whose program name is this one, e.g. `seance`.
    case program(String)
    /// Assets whose whole lowercased file name matches this lowercased
    /// pattern, where `*` stands for any run of characters and `?` for one.
    case pattern(String)

    // MARK: - Parsing

    /// Reads a filter as the user typed it; nil when blank. A file name counts
    /// as its program and a download link as its file name, so `Seance`,
    /// `seance-macos-universal.zip` and a link to that file all name the
    /// program `seance`. Input that could select nothing in particular is
    /// refused rather than silently tracking every program.
    public static func parse(_ input: String) throws -> AssetFilter? {
        let input = input.trimmingCharacters(in: .whitespacesAndNewlines)
        if input.isEmpty { return nil }

        let fileName = input.contains("://") ? try linkFileName(input) : input
        if fileName.contains(where: { wildcards.contains($0) }) {
            guard fileName.contains(where: { $0.isLetter || $0.isNumber }) else {
                throw ObtainintoshError("The pattern \"\(input)\" matches every file. Leave the program blank "
                    + "to let Obtainintosh choose.")
            }
            return .pattern(fileName.lowercased())
        }

        guard let name = programName(fileName) else {
            throw ObtainintoshError("\"\(input)\" is not a program name. Enter the name the program's release "
                + "files start with, such as seance for seance-macos-universal.zip.")
        }
        return .program(name)
    }

    /// The canonical form of a filter as the user typed it, nil when blank.
    public static func canonicalize(_ input: String) throws -> String? {
        try parse(input)?.canonical
    }

    /// The form stored with an entry and compared to tell entries apart.
    /// Parsing it yields this filter again.
    public var canonical: String {
        switch self {
        case .program(let name), .pattern(let name): return name
        }
    }

    public func matches(_ fileName: String) -> Bool {
        switch self {
        case .program(let name): return Self.programName(fileName) == name
        case .pattern(let pattern): return Self.wildcardMatch(pattern, fileName.lowercased())
        }
    }

    // MARK: - Program names

    /// Characters that make a filter a file name pattern rather than a
    /// program name. Neither appears in a release asset's file name.
    private static let wildcards: Set<Character> = ["*", "?"]

    /// Packaging suffixes removed before a file name is split into words, so
    /// `tar` and `gz` cannot continue a program name. Composite suffixes come
    /// before the shorter ones they end with: the first match wins.
    static let packageSuffixes = [
        ".app.tar.gz", ".tar.gz", ".tar.xz", ".tar.bz2", ".tar.zst", ".appimage", ".flatpak", ".dmg", ".pkg",
        ".zip", ".deb", ".rpm", ".tgz", ".snap", ".apk", ".ipa", ".exe", ".msi", ".7z", ".tar", ".gz", ".xz",
        ".bz2", ".zst",
        // Font files, as in FontFile.extensions.
        ".ttf", ".otf", ".ttc", ".otc",
    ]

    /// Operating system names. Every marker the platform picker recognises
    /// is here, so a program name always ends before the platform part of a
    /// file name, also when a version is fused on (`macos14`, `win11`).
    static let osWords: Set<String> = [
        "mac", "macos", "macosx", "osx", "darwin", "apple", "linux", "linux32", "linux64", "ubuntu",
        "debian", "fedora", "rhel", "centos", "alpine", "windows", "win", "win32", "win64", "android",
        "ios", "ipados", "tvos", "watchos", "freebsd", "openbsd", "netbsd", "solaris", "illumos",
    ]

    /// Words that describe a build rather than the program: architectures
    /// (`x86_64` splits into `x86` and `64`), Apple Silicon spellings, libc
    /// and toolchain names from target triples, and packaging variants.
    /// `cli`, `sync` or `nightly` are deliberately absent: they tell
    /// programs or channels apart.
    static let buildWords: Set<String> = [
        "universal", "universal2", "arm64", "arm64e", "aarch64", "arm", "armv6l", "armv7l", "armv8", "x86",
        "x64", "amd64", "intel", "silicon", "applesilicon", "gnu", "musl", "msvc", "mingw", "static",
        "portable", "installer", "setup", "standalone", "bundle", "bin",
    ]

    /// Shortest commit hash treated as one; `git describe` abbreviates to 7.
    private static let minimumCommitHashLength = 7

    /// The program a release asset belongs to: the leading words of its file
    /// name, up to the first word that describes the build instead.
    ///
    ///     seance_1.9.0-1_amd64.deb          → seance
    ///     seance-sync-macos-arm64.tar.gz    → seance-sync
    ///     Mac-Mouse-Fix-3.0.dmg             → mac-mouse-fix   (first word always counts)
    ///     1.0-linux.tar.gz                  → nil             (only a version)
    public static func programName(_ fileName: String) -> String? {
        let words = words(of: fileName)
        guard let first = words.first, !isBareVersion(first) else { return nil }

        var name = [first]
        for word in words.dropFirst() {
            if describesBuild(word) { break }
            name.append(word)
        }
        return name.joined(separator: "-")
    }

    /// The release file a download link points at:
    /// `https://host/o/r/releases/download/v1/seance.zip?x=1` → `seance.zip`.
    /// A link to anything else, such as the repository, names no program.
    private static func linkFileName(_ link: String) throws -> String {
        let path = link.beforeQueryOrFragment()
        let fileName = path.split(separator: "/", omittingEmptySubsequences: true).last.map(String.init) ?? path
        let lower = fileName.lowercased()
        if packageSuffixes.contains(where: { lower.hasSuffix($0) }) { return fileName }
        throw ObtainintoshError("\"\(link)\" is not a link to a release file. Enter the program's name instead, "
            + "such as seance for seance-macos-universal.zip.")
    }

    /// The lowercase words of a file name without its packaging suffix.
    /// Unicode letters count as word characters, so `séance` stays one word.
    private static func words(of fileName: String) -> [String] {
        let lower = fileName.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        var base = lower
        if let suffix = packageSuffixes.first(where: { lower.hasSuffix($0) }) {
            base = String(lower.dropLast(suffix.count))
        }
        return base.split(whereSeparator: { !($0.isLetter || $0.isNumber) }).map(String.init)
    }

    private static func describesBuild(_ word: String) -> Bool {
        isVersion(word) || isCommitHash(word) || isVersionedOS(word) || isAppleChip(word)
            || osWords.contains(word) || buildWords.contains(word) || AssetPicker.unsupportedCPUMarkers.contains(word)
    }

    /// `1`, `2024`, `v2`, `v2beta`: any word that starts with a number.
    private static func isVersion(_ word: String) -> Bool {
        let digits = word.hasPrefix("v") ? word.dropFirst() : Substring(word)
        return digits.first?.isASCIIDigit == true
    }

    /// `1` or `v2`, but not `7zip`: a first word that is nothing but a
    /// version leaves the file name without a program.
    private static func isBareVersion(_ word: String) -> Bool {
        let digits = word.hasPrefix("v") ? word.dropFirst() : Substring(word)
        return !digits.isEmpty && digits.allSatisfy(\.isASCIIDigit)
    }

    /// A commit hash, bare (`3f9a2c1`) or as `git describe` writes it
    /// (`g3f9a2c1`). It changes with every build, so letting it into the
    /// program name would make the name unmatchable by the next release. A
    /// hex word without digits (`facade`) is a word, not a hash.
    private static func isCommitHash(_ word: String) -> Bool {
        let hash = word.hasPrefix("g") ? word.dropFirst() : Substring(word)
        return hash.count >= minimumCommitHashLength && hash.allSatisfy(\.isASCIIHexDigit)
            && hash.contains(where: \.isASCIIDigit)
    }

    /// An Apple Silicon chip generation, `m1` onwards, so builds named for
    /// one (`tool-m4.dmg`) need no list update when the next chip ships. The
    /// price: such a word inside a program's own name (`bmw-m3-tools`) ends
    /// the name early, which a wildcard pattern works around.
    private static func isAppleChip(_ word: String) -> Bool {
        guard word.hasPrefix("m") else { return false }
        let generation = word.dropFirst()
        return (1...2).contains(generation.count) && generation.allSatisfy(\.isASCIIDigit)
    }

    /// An operating system name with its version fused on: `macos14`,
    /// `win11`, `ubuntu2204`.
    private static func isVersionedOS(_ word: String) -> Bool {
        guard let split = word.firstIndex(where: \.isASCIIDigit) else { return false }
        return osWords.contains(String(word[..<split])) && word[split...].allSatisfy(\.isASCIIDigit)
    }

    /// Whole-string match where `*` stands for any run of characters and `?`
    /// for exactly one. On a mismatch it backtracks to the most recent `*`
    /// only, which suffices: a later `*` can absorb anything an earlier one
    /// could.
    static func wildcardMatch(_ pattern: String, _ text: String) -> Bool {
        let pattern = Array(pattern)
        let text = Array(text)
        var p = 0
        var t = 0
        // The last `*` seen, and the text position it currently absorbs up to.
        var star: (pattern: Int, text: Int)?

        while t < text.count {
            if p < pattern.count, pattern[p] == "*" {
                star = (p, t)
                p += 1
            } else if p < pattern.count, pattern[p] == "?" || pattern[p] == text[t] {
                p += 1
                t += 1
            } else {
                guard let last = star else { return false }
                star = (last.pattern, last.text + 1)
                p = last.pattern + 1
                t = last.text + 1
            }
        }
        return pattern[p...].allSatisfy { $0 == "*" }
    }
}
