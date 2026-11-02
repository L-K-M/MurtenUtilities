import Foundation

/// Where alert notifications go. In Murten Utilities the suite owns
/// notifications (its opt-in suggestion notifications), so the module ships
/// no poster of its own; tests supply fakes.
public protocol NotificationPosting: Sendable {
    func requestPermission() async -> Bool
    func post(identifier: String, title: String, body: String) async throws
}
