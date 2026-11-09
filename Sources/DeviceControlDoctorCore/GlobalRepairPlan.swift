import Foundation

/// The explicit service-wide repair used by Reset All. Keeping this separate
/// from `RepairPlan` prevents an ordinary per-app repair from accidentally
/// dropping its bundle-identifier scope.
public struct GlobalRepairPlan: Sendable {
    public let services = ResetService.allCases

    public init() {}

    public var arguments: [[String]] {
        services.map { ["reset", $0.rawValue] }
    }
}
