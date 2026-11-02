import Foundation

/// Identifies the suite to the forges; GitHub requires a User-Agent.
public enum ObtainintoshUserAgent {
    public static let value: String = {
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev"
        return "MurtenUtilities/\(version) (Obtainintosh)"
    }()
}
