import Foundation
import Testing
import HallPassCore
import MurtenCore
import MurtenModuleKit
@testable import HallPassModule

/// What the suite sees of HallPass: an on-demand pane with no watcher,
/// no route actions, and a quit warning for unsaved or running work.
@MainActor
struct HallPassProviderTests {
    private let baseline = NetworkConfiguration(wifi: ["169.254.0.0/16"], ethernet: nil)

    @Test func matchesAnAvailableRegistryEntry() {
        let descriptor = ModuleRegistry.all.first { $0.id == HallPassProvider.moduleID }
        #expect(descriptor?.status == .available)
    }

    @Test func isAnOnDemandPane() async {
        let sandbox = Sandbox()
        defer { sandbox.cleanUp() }
        let provider = HallPassProvider(context: ModuleContext(
            moduleID: HallPassProvider.moduleID, defaults: sandbox.defaults,
            requestRecheck: {}, open: { _ in }))

        // AnyView and WatcherRegistration are not Equatable; compare outside #expect.
        let hasWatcher = provider.watch != nil
        let hasSettings = provider.makeSettings() != nil
        let hasMenuSection = provider.makeMenuSection() != nil
        let hasWindow = provider.makeWindow(ModuleWindowRequest(moduleID: "hallpass", kind: "anything")) != nil

        #expect(provider.moduleID == "hallpass")
        #expect(!hasWatcher, "reads need administrator access, so nothing may poll")
        #expect(provider.routeActions.isEmpty)
        #expect(await provider.applicability() == .applicable)
        #expect(!hasSettings)
        #expect(!hasMenuSection)
        #expect(!hasWindow)
        #expect(provider.interruptionWarning == nil)
    }

    @Test func routesCarryNoActionOrPreselection() throws {
        let sandbox = Sandbox()
        defer { sandbox.cleanUp() }
        let provider = HallPassProvider(model: sandbox.model(try FakePreferences(baseline: baseline)))
        let allowlist = RouteAllowlist(modules: [provider.moduleID], actions: [provider.moduleID: provider.routeActions])

        #expect(throws: Never.self) { try allowlist.validate(ModuleRoute(moduleID: "hallpass")) }
        #expect(throws: RouteError.unknownAction("apply")) {
            try allowlist.validate(ModuleRoute(moduleID: "hallpass", action: "apply", context: ["wifi": "10.0.0.0/8"]))
        }
    }

    @Test func warnsAboutAnUnsavedDraft() async throws {
        let sandbox = Sandbox()
        defer { sandbox.cleanUp() }
        let model = sandbox.model(try FakePreferences(baseline: baseline))
        let provider = HallPassProvider(model: model)

        await model.load()
        #expect(provider.interruptionWarning == nil)

        try model.add("192.168.1.0/24", interfaces: [.wifi])
        #expect(provider.interruptionWarning == "Unsaved changes to local-network exemptions")

        // Navigating home and back rebuilds the pane, not the draft.
        _ = provider.makePane(route: nil)
        #expect(model.isDirty)

        model.discard()
        #expect(provider.interruptionWarning == nil)
    }

    @Test func warnsWhileApplying() async throws {
        let sandbox = Sandbox()
        defer { sandbox.cleanUp() }
        let service = try FakePreferences(baseline: baseline, holdCalls: true)
        let model = sandbox.model(service)
        let provider = HallPassProvider(model: model)

        let loading = Task { await model.load() }
        #expect(await eventually { await service.holding })
        #expect(provider.interruptionWarning == "Reading the current exemptions")
        await service.release()
        await loading.value

        try model.add("192.168.1.0/24", interfaces: [.wifi])
        let applying = Task { await model.save() }
        #expect(await eventually { await service.holding })
        #expect(provider.interruptionWarning == "Applying changes")
        await service.release()
        await applying.value

        #expect(provider.interruptionWarning == nil)
        #expect(model.needsRestart)
    }
}
