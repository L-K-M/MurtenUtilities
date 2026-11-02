import Foundation

/// The CPU an asset must run on. The suite ships universal, so the running
/// slice decides: an Apple Silicon Mac prefers arm64 builds, an Intel Mac
/// cannot run them.
public enum CPUArchitecture: Sendable {
    case arm64
    case x86_64

    public static var current: CPUArchitecture {
        #if arch(arm64)
        return .arm64
        #else
        return .x86_64
        #endif
    }
}
