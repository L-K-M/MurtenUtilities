import Foundation

/// `osascript` arguments for the classic login-item actions. The path goes to
/// the script's run handler as an argument and is never spliced into
/// AppleScript source: a login item's path is data any app can choose, and a
/// quote in it must not become code running with the suite's privacy grants.
enum LoginItemScript {
    static let executable = "/usr/bin/osascript"

    /// Deletes every login item whose path is `path`; nil unless absolute.
    static func removal(path: String) -> [String]? {
        arguments(path: path,
                  statement: "tell application \"System Events\" to delete (every login item whose path is itemPath)")
    }

    /// Re-adds a login item for `path`; nil unless absolute.
    static func restoration(path: String) -> [String]? {
        arguments(path: path,
                  statement: "tell application \"System Events\" to make login item at end with properties {path:itemPath, hidden:false}")
    }

    /// An absolute path also cannot be mistaken for an `osascript` option.
    private static func arguments(path: String, statement: String) -> [String]? {
        guard path.hasPrefix("/") else { return nil }
        return ["-e", "on run argv", "-e", "set itemPath to item 1 of argv",
                "-e", statement, "-e", "end run", path]
    }
}
