import SwiftUI
import BootCaptainCore

/// Says how many startup items appeared since the user last reviewed the
/// list, and lets them mark the current list as reviewed. The suite's
/// background check compares against that list.
struct ReviewBar: View {
    @EnvironmentObject var scan: ScanViewModel

    var body: some View {
        let count = scan.unreviewedItems.count
        if scan.review == .unreadable {
            bar(message: "The list of reviewed startup items could not be read.", showAction: false)
        } else if count > 0 {
            bar(message: "\(count) startup item\(count == 1 ? " is" : "s are") new since your last review\(reviewedDate).",
                showAction: scan.filter != .unreviewed)
        }
    }

    private var reviewedDate: String {
        guard case .reviewed(let inventory) = scan.review else { return "" }
        return " on \(inventory.reviewedAt.formatted(date: .abbreviated, time: .shortened))"
    }

    private func bar(message: String, showAction: Bool) -> some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: 10) {
                Image(systemName: "sparkles")
                    .foregroundStyle(.blue)
                    .accessibilityHidden(true)
                Text(message).font(.callout)
                Spacer()
                if showAction {
                    Button("Show New Items") { scan.showUnreviewed() }
                        .buttonStyle(.borderless)
                }
                Button("Mark as Reviewed") { scan.markReviewed() }
                    .disabled(scan.isScanning)
                    .help("Treat the current list as reviewed; only items added later are reported as new.")
            }
            .padding(.horizontal, 14).padding(.vertical, 7)
        }
        .background(.bar)
    }
}
