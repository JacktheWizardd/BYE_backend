import Combine
import Foundation
import Sparkle

/// Sparkle wrapper. Only distribution builds carry `SUFeedURL` and `SUPublicEDKey`
/// in Info.plist; test, debug, audit and evaluation builds stay inert and never
/// contact the update feed.
@MainActor
final class AppUpdater: ObservableObject {
    @Published private(set) var canCheckForUpdates = false
    let isEnabled: Bool
    private let controller: SPUStandardUpdaterController?

    init(info: [String: Any]? = Bundle.main.infoDictionary) {
        isEnabled = AppUpdater.isConfigured(info: info)
        guard isEnabled else {
            controller = nil
            return
        }
        let controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        self.controller = controller
        controller.updater.publisher(for: \.canCheckForUpdates).assign(to: &$canCheckForUpdates)
    }

    /// Both a feed and the EdDSA public key are required; Sparkle refuses
    /// unsigned updates, so a feed without a key is treated as unconfigured.
    nonisolated static func isConfigured(info: [String: Any]?) -> Bool {
        guard let feed = (info?["SUFeedURL"] as? String)?.trimmingCharacters(in: .whitespaces),
              let key = (info?["SUPublicEDKey"] as? String)?.trimmingCharacters(in: .whitespaces),
              !key.isEmpty,
              let url = URL(string: feed),
              let scheme = url.scheme?.lowercased() else { return false }
        return scheme == "https" || (scheme == "http" && ["127.0.0.1", "localhost"].contains(url.host ?? ""))
    }

    func checkForUpdates() { controller?.checkForUpdates(nil) }

    var automaticallyChecksForUpdates: Bool {
        get { controller?.updater.automaticallyChecksForUpdates ?? false }
        set {
            objectWillChange.send()
            controller?.updater.automaticallyChecksForUpdates = newValue
        }
    }

    var automaticallyDownloadsUpdates: Bool {
        get { controller?.updater.automaticallyDownloadsUpdates ?? false }
        set {
            objectWillChange.send()
            controller?.updater.automaticallyDownloadsUpdates = newValue
        }
    }
}
