import AppKit
import SwiftUI
import DoctorCore
import MurtenModuleKit

/// The standalone app's menu-bar extra, folded into the suite's companion:
/// the watch list's size, how many apps need review, a manual refresh and
/// the Test Pad. Opening the app and quitting are the companion's own.
struct DoctorMenuSection: View {
    @EnvironmentObject private var doctor: DoctorStore
    @Environment(\.openWindow) private var openWindow

    private var reviewCount: Int {
        doctor.apps.filter { $0.hasDeniedExpectedPermission || $0.hasFailedTest }.count
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(doctor.apps.count == 1 ? "1 watched app" : "\(doctor.apps.count) watched apps")
            if reviewCount > 0 {
                Text(reviewCount == 1 ? "1 app needs review" : "\(reviewCount) apps need review")
                    .foregroundStyle(.orange)
            }
            HStack {
                Button(doctor.isChecking ? "Checking…" : "Refresh Permissions") { doctor.refresh() }
                    .disabled(doctor.isChecking || doctor.isRepairing)
                Button("Open Test Pad") {
                    openWindow(module: .testPad)
                    NSApp.activate()
                }
            }
            .controlSize(.small)
        }
        .font(.callout)
    }
}
