import AppKit
import Combine
import CoreText
import Sparkle
import SwiftUI

// This product deliberately has no dependency on ClasswiseCore or BYEAPI.
enum RetirementPolicy {
    static let site = "https://bye-before-you-enroll.pages.dev"
    static let bundleID = "local.classwise.mac.apple-ai-beta"
    static func allowsFeed(_ value: String, verification: Bool = false) -> Bool {
        guard let url = URL(string: value), url.user == nil, url.password == nil,
              url.query == nil, url.fragment == nil else { return false }
        if value == site + "/updates/appcast.xml" { return true }
        return verification && url.scheme == "http" && ["127.0.0.1", "localhost"].contains(url.host ?? "") && url.path == "/appcast.xml"
    }
    static func revealURL(bundle: Bundle = .main) -> URL? {
        let url = bundle.bundleURL.standardizedFileURL
        guard [bundleID, "local.classwise.mac.test", "local.classwise.mac.update-test"].contains(bundle.bundleIdentifier ?? ""),
              url.pathExtension == "app", url.resolvingSymlinksInPath() == url else { return nil }
        return url
    }
}

@MainActor
final class RetirementUpdater: ObservableObject {
    @Published private(set) var canCheck = false
    private var controller: SPUStandardUpdaterController?
    init(bundle: Bundle = .main) {
        let verification = bundle.bundleIdentifier != RetirementPolicy.bundleID
        guard let feed = bundle.object(forInfoDictionaryKey: "SUFeedURL") as? String,
              RetirementPolicy.allowsFeed(feed, verification: verification),
              let key = bundle.object(forInfoDictionaryKey: "SUPublicEDKey") as? String, !key.isEmpty else { return }
        let updater = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil, userDriverDelegate: nil)
        controller = updater
        updater.updater.publisher(for: \.canCheckForUpdates).assign(to: &$canCheck)
    }
    func check() { controller?.checkForUpdates(nil) }
}

@main
struct RetirementApp: App {
    @StateObject private var updater = RetirementUpdater()
    init() {
        for name in ["LibreBaskerville-Bold.ttf", "SchibstedGrotesk-Regular.ttf"] {
            if let url = Bundle.main.resourceURL?.appendingPathComponent(name), FileManager.default.fileExists(atPath: url.path) {
                CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
    }
    var body: some Scene {
        WindowGroup("BYE") {
            VStack(alignment: .leading, spacing: 20) {
                Text("BYE").font(.custom("LibreBaskerville-Bold", size: 34))
                Text("BYE has shut down.").font(.custom("LibreBaskerville-Bold", size: 27))
                Text("Search, ratings, reviews and account features have been removed from this version. Only application updates remain available.")
                Text("You can remove BYE by quitting and moving the app to the Trash. This application does not delete files.")
                    .foregroundStyle(Color(red: 0.42, green: 0.40, blue: 0.37))
                Text("Version \(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.5.1")")
                    .font(.system(size: 13, design: .monospaced))
                ViewThatFits {
                    HStack { controls }
                    VStack(alignment: .leading) { controls }
                }
            }
            .font(.system(size: 17))
            .padding(32).frame(minWidth: 360, idealWidth: 620, maxWidth: .infinity, minHeight: 420, maxHeight: .infinity, alignment: .center)
            .background(Color(red: 0.98, green: 0.973, blue: 0.953))
            .foregroundStyle(Color(red: 0.086, green: 0.086, blue: 0.094))
            .preferredColorScheme(.light)
        }
        .defaultSize(width: 660, height: 480)
        .commands {
            CommandGroup(after: .appInfo) { Button("Check for updates…") { updater.check() }.disabled(!updater.canCheck) }
            CommandGroup(replacing: .newItem) {}
        }
    }
    @ViewBuilder private var controls: some View {
        Button("Check for updates") { updater.check() }.disabled(!updater.canCheck).frame(minHeight: 44)
        Button("Show application folder") {
            if let url = RetirementPolicy.revealURL() { NSWorkspace.shared.activateFileViewerSelecting([url]) }
        }.disabled(RetirementPolicy.revealURL() == nil).frame(minHeight: 44)
        Button("Quit") { NSApplication.shared.terminate(nil) }.keyboardShortcut("q").frame(minHeight: 44)
    }
}
