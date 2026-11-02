import Foundation

/// The user-facing wording of forge responses, shared by both clients.
public enum ForgeMessages {
    /// Shown for a visible repository whose release list is not found: its
    /// releases are turned off in its settings.
    public static let releasesTurnedOff = "This repository has its releases turned off and no font files to track."

    /// Shown when a Forgejo repository cannot be found, which is also how a
    /// private one looks to missing or wrong credentials.
    public static let repositoryNotFound = "Repository not found on this Forgejo instance. A private repository "
        + "also looks like this when the username or application key is missing or wrong."

    /// Turns the status codes a Forgejo instance answers with into advice,
    /// since the usual cause is a credential problem.
    public static func forgejoError(status: Int) -> String {
        switch status {
        case 401, 403:
            return "Forgejo rejected the credentials (HTTP \(status)). Check the username and application key, "
                + "and that the key has read access to the repository."
        default:
            return "Forgejo API error: \(statusText(status))"
        }
    }

    public static func gitHubError(status: Int) -> String {
        "GitHub API error: \(statusText(status))"
    }

    /// `404 Not Found`, or the bare number for an uncommon status.
    public static func statusText(_ status: Int) -> String {
        let reasons = [
            400: "Bad Request", 401: "Unauthorized", 403: "Forbidden", 404: "Not Found", 409: "Conflict",
            416: "Range Not Satisfiable", 429: "Too Many Requests", 500: "Internal Server Error",
            502: "Bad Gateway", 503: "Service Unavailable", 504: "Gateway Timeout",
        ]
        return reasons[status].map { "\(status) \($0)" } ?? "\(status)"
    }
}
