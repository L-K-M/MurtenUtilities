import Foundation

public enum TCCOutputParser {

    // MARK: - Query parsing

    public static func parseQuery(output: String, exitCode: Int32) -> AuthorizationResult {
        // Exit 64 (usage) or 77 (sandbox/Operation not permitted) → unavailable
        if exitCode == 64 {
            return AuthorizationResult(
                state: .unavailable,
                detail: trimDetail(output, limit: 1200, fallback: "tccutil returned exit code 64 (usage error)")
            )
        }
        if exitCode == 77 {
            return AuthorizationResult(
                state: .unavailable,
                detail: trimDetail(output, limit: 1200, fallback: "tccutil returned exit code 77 (sandbox/permission denied)")
            )
        }

        let normalized = output.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()

        // Determine state from output text
        let outputState: AuthorizationState?
        if normalized == "granted" {
            outputState = .granted
        } else if normalized == "denied" {
            outputState = .denied
        } else if normalized == "limited" {
            outputState = .limited
        } else if normalized.isEmpty {
            outputState = nil
        } else {
            outputState = nil
        }

        // Determine state from exit code
        let exitState: AuthorizationState?
        switch exitCode {
        case 0:  exitState = .granted
        case 1:  exitState = .denied
        case 2:  exitState = .limited
        default: exitState = nil
        }

        // Both must agree; mismatch → unknown
        if let oState = outputState, let eState = exitState, oState == eState {
            return AuthorizationResult(
                state: oState,
                detail: defaultDetail(for: oState)
            )
        }

        // Mismatched, blank, unknown output, or arbitrary failure → unknown
        let reason: String
        if let oState = outputState, let eState = exitState, oState != eState {
            reason = "Output and exit code disagree (output: \(oState.rawValue), exit: \(eState.rawValue))"
        } else if outputState == nil, let eState = exitState {
            reason = "Output did not match any known state (exit code suggests \(eState.rawValue))"
        } else if let oState = outputState, exitState == nil {
            reason = "Exit code did not match any known state (output suggests \(oState.rawValue))"
        } else {
            reason = "Could not determine authorization state from output or exit code"
        }

        return AuthorizationResult(
            state: .unknown,
            detail: trimDetail(output, limit: 1200, fallback: reason)
        )
    }

    // MARK: - Client listing

    public static func parseClients(output: String) -> [String] {
        var seen = Set<String>()
        var result: [String] = []

        for line in output.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)

            // Skip empty lines
            guard !trimmed.isEmpty else { continue }

            // Skip heading lines like "granted:", "denied:", "usage:", "error:"
            let lower = trimmed.lowercased()
            if lower.hasSuffix(":") && !lower.contains(" ") {
                continue
            }

            // Skip obvious error/usage text
            if lower.hasPrefix("error:") || lower.hasPrefix("usage:") || lower.hasPrefix("note:") {
                continue
            }

            // Accept bundle identifiers
            if ClientIdentifier.isBundleIdentifier(trimmed) {
                if seen.insert(trimmed).inserted {
                    result.append(trimmed)
                }
                continue
            }

            // Accept safe absolute paths
            if trimmed.hasPrefix("/") && !trimmed.hasPrefix("//") {
                if seen.insert(trimmed).inserted {
                    result.append(trimmed)
                }
                continue
            }

            // Skip anything else (malformed lines, error text, etc.)
        }

        return result
    }

    // MARK: - Help detection

    public static func supportsListing(help: String) -> Bool {
        let lines = help.components(separatedBy: .newlines)
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
            // Must contain a list syntax with both -s and -b flags
            // e.g. "list -s <service> -b <bundle>" or similar
            if trimmed.range(of: "\\blist\\s", options: .regularExpression) != nil && trimmed.contains("-s") && trimmed.contains("-b") {
                return true
            }
        }
        return false
    }

    // MARK: - Private helpers

    private static func defaultDetail(for state: AuthorizationState) -> String {
        switch state {
        case .granted:  return "Access has been granted"
        case .denied:   return "Access has been denied"
        case .limited:  return "Access is limited"
        case .unknown:  return "Authorization state could not be determined"
        case .unavailable: return "Unable to query authorization (usage error or sandbox restriction)"
        }
    }

    private static func trimDetail(_ output: String, limit: Int, fallback: String) -> String {
        let trimmed = output.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return fallback }
        if trimmed.count <= limit { return trimmed }
        return String(trimmed.prefix(limit))
    }
}
