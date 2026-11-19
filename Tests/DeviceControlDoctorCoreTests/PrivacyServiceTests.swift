import XCTest
@testable import DoctorCore

final class PrivacyServiceTests: XCTestCase {
    func testCameraLookup() {
        let service = PrivacyService.named("kTCCServiceCamera")

        XCTAssertEqual(service.title, "Camera")
        XCTAssertEqual(service.settingsAnchor, "Privacy_Camera")
        XCTAssertEqual(service.resetName, "Camera")
        XCTAssertEqual(service.risk, .standard)
        XCTAssertFalse(service.settingsCanRemove)
        XCTAssertEqual(service.settingsPageTitle, "Camera")
    }

    func testFullDiskAccessLookup() {
        let service = PrivacyService.named("kTCCServiceSystemPolicyAllFiles")

        XCTAssertEqual(service.title, "Full Disk Access")
        XCTAssertEqual(service.risk, .high)
        XCTAssertTrue(service.settingsCanRemove)
        XCTAssertEqual(service.settingsPageTitle, "Full Disk Access")
        XCTAssertEqual(service.resetName, "SystemPolicyAllFiles")
    }

    func testUnknownServiceIsDerived() {
        let service = PrivacyService.named("kTCCServiceFooBarBaz")

        XCTAssertEqual(service.title, "Foo Bar Baz")
        XCTAssertNil(service.settingsAnchor)
        XCTAssertEqual(service.risk, .standard)
        XCTAssertNil(service.settingsPageTitle)
        XCTAssertEqual(service.resetName, "FooBarBaz")
    }

    func testDerivedTitleSplitsCamelCase() {
        XCTAssertEqual(PrivacyService.derivedTitle("kTCCServiceSystemPolicyFooBar"), "System Policy Foo Bar")
    }

    func testKnownIdentifiersAreUniqueAndPrefixed() {
        let identifiers = PrivacyService.known.map(\.identifier)

        XCTAssertEqual(Set(identifiers).count, identifiers.count)
        XCTAssertTrue(identifiers.allSatisfy { $0.hasPrefix("kTCCService") })
    }

    func testSettingsPageTitles() {
        XCTAssertEqual(PrivacyService.named("kTCCServicePostEvent").settingsPageTitle, "Accessibility")
        XCTAssertEqual(PrivacyService.named("kTCCServiceSystemPolicyDesktopFolder").settingsPageTitle, "Files & Folders")
        XCTAssertEqual(PrivacyService.named("kTCCServiceAudioCapture").settingsPageTitle, "Screen & System Audio Recording")
    }

    func testDeviceControlTitlesMatchPermissionService() {
        XCTAssertEqual(PrivacyService.named("kTCCServiceAccessibility").title, PermissionService.accessibility.title)
        XCTAssertEqual(PrivacyService.named("kTCCServicePostEvent").title, PermissionService.postEvent.title)
        XCTAssertEqual(PrivacyService.named("kTCCServiceListenEvent").title, PermissionService.listenEvent.title)
    }
}
