import SwiftUI

/// DockVac's tab in the suite's Settings. Its one choice stays off by default: a
/// background check must never prompt, and over SSH only the user can accept that risk.
struct DockVacSettings: View {
  /// Re-runs the watcher, so the choice takes effect without waiting an hour.
  let requestRecheck: () -> Void
  /// In the module's own defaults, which the suite installs as this view's store.
  @AppStorage(SSHBackgroundPreference.key) private var checksSSHEndpoints = false

  var body: some View {
    Form {
      Toggle("Check SSH endpoints in the background", isOn: $checksSSHEndpoints)
      Text(
        """
        When Docker runs on a server you reach over SSH, the background check skips it and \
        DockVac checks it when you open the tool. Turn this on to include the server in the \
        hourly check. DockVac never asks for a password or passphrase, but an SSH agent \
        that confirms each use of a key, such as 1Password or Secretive, may ask you to \
        approve the connection while you are doing something else.
        """
      )
      .font(.callout)
      .foregroundStyle(.secondary)
      .fixedSize(horizontal: false, vertical: true)
    }
    .padding()
    .frame(width: 460)
    .onChange(of: checksSSHEndpoints) { requestRecheck() }
  }
}
