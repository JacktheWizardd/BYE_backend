import SwiftUI

struct UpdateSettingsView: View {
    @ObservedObject var updater: AppUpdater

    private var version: String {
        let info = Bundle.main.infoDictionary
        let label = info?["CFBundleGetInfoString"] as? String ?? info?["CFBundleShortVersionString"] as? String ?? "Development"
        let build = info?["CFBundleVersion"] as? String ?? "—"
        return "\(label) (build \(build))"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Eyebrow(title: "Updates")
            if updater.isEnabled {
                Toggle("Check for updates automatically", isOn: $updater.automaticallyChecksForUpdates)
                Toggle("Download and install updates automatically", isOn: $updater.automaticallyDownloadsUpdates)
                    .disabled(!updater.automaticallyChecksForUpdates)
                Text("BYE checks the BYE website about once a day. The website’s host, Cloudflare, sees your IP address and app version; no other information is sent.")
                    .font(.system(size: 11)).foregroundStyle(Palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Button("Check for Updates…") { updater.checkForUpdates() }
                    .disabled(!updater.canCheckForUpdates)
            } else if NetworkShutdown.isActive {
                Text("This is BYE’s final version. It no longer checks for updates or connects to the internet.")
                    .font(.system(size: 12)).foregroundStyle(Palette.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            } else {
                Text("Updates are not available in this build.")
                    .font(.system(size: 12)).foregroundStyle(Palette.secondary)
            }
            Divider()
            Text(version).font(.system(size: 11)).foregroundStyle(Palette.secondary)
        }
        .padding(22)
        .frame(width: 420, alignment: .leading)
    }
}
