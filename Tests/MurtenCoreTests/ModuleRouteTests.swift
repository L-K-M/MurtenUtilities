import XCTest
@testable import MurtenCore

final class ModuleRouteTests: XCTestCase {
    private let allowlist = RouteAllowlist(
        modules: ["dockvac", "repomen"],
        actions: ["dockvac": ["reclaim": ["endpoint"]]])

    func testRouteRoundTripsThroughItsURL() throws {
        let route = ModuleRoute(moduleID: "dockvac", action: "reclaim",
                                context: ["endpoint": "unix:///var/run/docker.sock"])
        XCTAssertEqual(try allowlist.route(from: route.url), route)
    }

    func testBareRouteOpensThePane() throws {
        let route = try allowlist.route(from: URL(string: "murten://repomen")!)
        XCTAssertEqual(route, ModuleRoute(moduleID: "repomen"))
    }

    func testRejectsForeignScheme() {
        XCTAssertThrowsError(try allowlist.route(from: URL(string: "https://dockvac/reclaim")!)) {
            XCTAssertEqual($0 as? RouteError, .wrongScheme)
        }
    }

    func testRejectsUnknownModuleActionAndContext() {
        XCTAssertThrowsError(try allowlist.route(from: URL(string: "murten://finder")!)) {
            XCTAssertEqual($0 as? RouteError, .unknownModule("finder"))
        }
        XCTAssertThrowsError(try allowlist.route(from: URL(string: "murten://dockvac/prune-all")!)) {
            XCTAssertEqual($0 as? RouteError, .unknownAction("prune-all"))
        }
        XCTAssertThrowsError(try allowlist.route(from: URL(string: "murten://dockvac/reclaim?command=rm")!)) {
            XCTAssertEqual($0 as? RouteError, .unexpectedContext("command"))
        }
        XCTAssertThrowsError(try allowlist.route(from: URL(string: "murten://repomen?path=/")!)) {
            XCTAssertEqual($0 as? RouteError, .unexpectedContext("path"))
        }
    }

    func testRejectsNestedPathsDuplicateKeysAndOversizedValues() {
        XCTAssertThrowsError(try allowlist.route(from: URL(string: "murten://dockvac/reclaim/now")!))
        XCTAssertThrowsError(try allowlist.route(from: URL(string: "murten://dockvac/reclaim?endpoint=a&endpoint=b")!))

        let long = String(repeating: "a", count: RouteAllowlist.maximumValueLength + 1)
        let route = ModuleRoute(moduleID: "dockvac", action: "reclaim", context: ["endpoint": long])
        XCTAssertThrowsError(try allowlist.validate(route)) {
            XCTAssertEqual($0 as? RouteError, .invalidValue("endpoint"))
        }
    }

    func testInvalidIdentifiersNeverTrapAndNeverParse() {
        for route in [ModuleRoute(moduleID: "Dock Vac"), ModuleRoute(moduleID: "dockvac", action: "re claim"),
                      ModuleRoute(moduleID: "DockVac")] {
            XCTAssertThrowsError(try allowlist.route(from: route.url), "\(route) must not round-trip")
        }
    }

    func testContextValuesWithReservedCharactersRoundTrip() throws {
        let route = ModuleRoute(moduleID: "dockvac", action: "reclaim",
                                context: ["endpoint": "ssh://me@host:22/?a=b&c=d#e"])
        XCTAssertEqual(try allowlist.route(from: route.url), route)
    }

    func testRejectsControlCharactersInValues() {
        let route = ModuleRoute(moduleID: "dockvac", action: "reclaim", context: ["endpoint": "a\nb"])
        XCTAssertThrowsError(try allowlist.validate(route))
    }
}
