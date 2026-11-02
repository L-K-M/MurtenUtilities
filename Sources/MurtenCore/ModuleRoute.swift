import Foundation

/// Where a suggestion, notification or tile click leads: a module, an
/// allowlisted action and typed context. Never a command or a path to run.
/// Notation: `murten://<moduleID>[/<action>][?key=value…]`, e.g.
/// `murten://dockvac/reclaim?endpoint=unix%3A%2F%2F%2Fvar%2Frun%2Fdocker.sock`.
/// The app does not register the scheme; URLs are an internal round-trip
/// format (notification payloads), validated on the way back in.
public struct ModuleRoute: Hashable, Codable, Sendable {
    public static let scheme = "murten"

    public let moduleID: String
    public let action: String?
    public let context: [String: String]

    public init(moduleID: String, action: String? = nil, context: [String: String] = [:]) {
        self.moduleID = moduleID
        self.action = action
        self.context = context
    }

    public var url: URL {
        var components = URLComponents()
        components.scheme = Self.scheme
        components.host = moduleID
        components.path = action.map { "/" + $0 } ?? ""
        if !context.isEmpty {
            components.queryItems = context.keys.sorted().map { URLQueryItem(name: $0, value: context[$0]) }
        }
        // Components built from validated identifiers always form a URL.
        return components.url ?? URL(string: "\(Self.scheme)://\(moduleID)")!
    }
}

public enum RouteError: Error, Equatable {
    case malformed
    case wrongScheme
    case unknownModule(String)
    case unknownAction(String)
    case unexpectedContext(String)
    case invalidValue(String)
}

/// The routes the app accepts: known modules, each module's actions, and the
/// context keys each action may carry. Anything else is rejected rather than
/// passed to a pane.
public struct RouteAllowlist: Sendable {
    public static let maximumValueLength = 256

    private let modules: Set<String>
    /// moduleID → action → permitted context keys.
    private let actions: [String: [String: Set<String>]]

    public init(modules: Set<String>, actions: [String: [String: Set<String>]] = [:]) {
        self.modules = modules
        self.actions = actions
    }

    /// Returns the route unchanged when every part is allowlisted.
    public func validate(_ route: ModuleRoute) throws -> ModuleRoute {
        guard modules.contains(route.moduleID) else { throw RouteError.unknownModule(route.moduleID) }

        guard let action = route.action else {
            // A bare route opens the pane and carries no context.
            if let key = route.context.keys.sorted().first { throw RouteError.unexpectedContext(key) }
            return route
        }

        guard let permittedKeys = actions[route.moduleID]?[action] else {
            throw RouteError.unknownAction(action)
        }

        for (key, value) in route.context {
            guard permittedKeys.contains(key) else { throw RouteError.unexpectedContext(key) }
            guard Self.isAcceptableValue(value) else { throw RouteError.invalidValue(key) }
        }
        return route
    }

    /// Parses and validates `murten://…`.
    public func route(from url: URL) throws -> ModuleRoute {
        guard let components = URLComponents(url: url, resolvingAgainstBaseURL: false) else {
            throw RouteError.malformed
        }
        guard components.scheme?.lowercased() == ModuleRoute.scheme else { throw RouteError.wrongScheme }
        guard let moduleID = components.host, Self.isIdentifier(moduleID) else { throw RouteError.malformed }

        let segments = components.path.split(separator: "/", omittingEmptySubsequences: true).map(String.init)
        guard segments.count <= 1 else { throw RouteError.malformed }

        let action = segments.first
        if let action, !Self.isIdentifier(action) { throw RouteError.malformed }

        var context: [String: String] = [:]
        for item in components.queryItems ?? [] {
            // A repeated key is ambiguous; reject instead of picking one.
            guard context[item.name] == nil else { throw RouteError.malformed }
            context[item.name] = item.value ?? ""
        }

        return try validate(ModuleRoute(moduleID: moduleID, action: action, context: context))
    }

    // MARK: - Character rules

    /// Lowercase ASCII letters, digits and hyphens, e.g. "dockvac", "reclaim-safe".
    private static func isIdentifier(_ string: String) -> Bool {
        !string.isEmpty && string.unicodeScalars.allSatisfy { scalar in
            ("a"..."z").contains(scalar) || ("0"..."9").contains(scalar) || scalar == "-"
        }
    }

    private static func isAcceptableValue(_ value: String) -> Bool {
        value.count <= maximumValueLength
            && !value.unicodeScalars.contains { CharacterSet.controlCharacters.contains($0) }
    }
}
