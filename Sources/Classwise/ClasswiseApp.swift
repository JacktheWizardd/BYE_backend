import SwiftUI
import ClasswiseCore

@main
struct ClasswiseApp: App {
    @NSApplicationDelegateAdaptor(BYEApplicationDelegate.self) private var applicationDelegate
    @StateObject private var model: AppModel
    #if BYE_AUDIT || BYE_MODEL_EVAL
    // Measurement builds never contact the update feed.
    @StateObject private var updater = AppUpdater(info: nil)
    #else
    @StateObject private var updater = AppUpdater()
    #endif
    init() {
        #if BYE_MODEL_EVAL
        let initial = ModelEvaluation.makeModel()
        #elseif BYE_AUDIT
        // A UI tool may relaunch a closed app without arguments. Fail before constructing network clients.
        guard let index = CommandLine.arguments.firstIndex(of: "--audit-session"),
              CommandLine.arguments.count > index + 1,
              !CommandLine.arguments[index + 1].hasPrefix("--") else {
            FileHandle.standardError.write(Data("Measurement build requires --audit-session; refusing unmetered startup.\n".utf8))
            exit(64)
        }
        let initial = AppAudit.makeModel(directory: URL(fileURLWithPath: CommandLine.arguments[index + 1]))
        #else
        var initial = AppModel()
        #endif
        #if DEBUG && !BYE_AUDIT && !BYE_MODEL_EVAL
        // Explicit acceptance mode keeps visual checks out of user preferences
        // while retaining this release’s disabled-summary policy.
        if let index = CommandLine.arguments.firstIndex(of: "--verification-storage"), CommandLine.arguments.count > index + 1 {
            let directory = URL(fileURLWithPath: CommandLine.arguments[index + 1], isDirectory: true)
            initial = AppModel(cache: ReportCache(directory: directory), choices: ProfileChoiceStore(directory: directory))
        }
        #endif
        _model = StateObject(wrappedValue: initial)
        NSApplication.shared.setActivationPolicy(.regular)
        // Swift Package runs from Xcode also need an icon without an app bundle.
        #if DEBUG
        let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns")
            ?? Bundle.module.url(forResource: "AppIcon", withExtension: "icns")
        #else
        // Avoid SwiftPM's absolute developer paths in distributed executables.
        let iconURL = Bundle.main.url(forResource: "AppIcon", withExtension: "icns")
            ?? Bundle(url: Bundle.main.bundleURL.appendingPathComponent("Classwise_Classwise.bundle"))?
                .url(forResource: "AppIcon", withExtension: "icns")
        #endif
        if let iconURL,
           let icon = NSImage(contentsOf: iconURL) {
            NSApplication.shared.applicationIconImage = icon
        }
        #if DEBUG
        if let index = CommandLine.arguments.firstIndex(of: "--verify-apple-quality"), CommandLine.arguments.count > index + 1 {
            let output = CommandLine.arguments[index + 1]
            Task { @MainActor in await LiveCheck.runAppleQuality(output: output) }
        }
        if let index = CommandLine.arguments.firstIndex(of: "--verify-apple"), CommandLine.arguments.count > index + 1 {
            let output = CommandLine.arguments[index + 1]
            Task { @MainActor in await LiveCheck.runApple(output: output) }
        }
        if let index = CommandLine.arguments.firstIndex(of: "--verify-matching"), CommandLine.arguments.count > index + 1 {
            let output = CommandLine.arguments[index + 1]
            Task { @MainActor in await LiveCheck.runMatching(output: output) }
        }
        if let index = CommandLine.arguments.firstIndex(of: "--verify-speed"), CommandLine.arguments.count > index + 1 {
            let output = CommandLine.arguments[index + 1]
            Task { @MainActor in await LiveCheck.runSpeed(output: output) }
        }
        if let index = CommandLine.arguments.firstIndex(of: "--verify-reviews"), CommandLine.arguments.count > index + 1 {
            let output = CommandLine.arguments[index + 1]
            Task { @MainActor in await LiveCheck.runReviewExpansion(output: output) }
        }
        if let index = CommandLine.arguments.firstIndex(of: "--verify-live"), CommandLine.arguments.count > index + 1 {
            let output = CommandLine.arguments[index + 1]
            Task { @MainActor in await LiveCheck.run(output: output) }
        }
        #endif
    }
    var body: some Scene {
        WindowGroup("BYE", id: "main") {
            ContentView(model: model)
                .background(MainWindowRegistration(owner: applicationDelegate))
                .frame(minWidth: 1000, minHeight: 700)
                .preferredColorScheme(.light)
                .onAppear {
                    NSApplication.shared.activate(ignoringOtherApps: true)
                    #if BYE_AUDIT
                    AppAudit.windowAppeared(model: model)
                    #endif
                    #if BYE_MODEL_EVAL
                    ModelEvaluation.windowAppeared(model: model)
                    #endif
                }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1180, height: 800)
        .commands {
            CommandGroup(after: .appInfo) {
                if updater.isEnabled {
                    Button("Check for Updates…") { updater.checkForUpdates() }.disabled(!updater.canCheckForUpdates)
                }
            }
            CommandGroup(replacing: .newItem) {
                Button("New search") { model.changeSearch(); applicationDelegate.reopenMainWindow() }.keyboardShortcut("n")
                Button("Refresh results") { model.refresh() }.keyboardShortcut("r").disabled(!model.showingResults || model.busy)
            }
        }
        Settings {
            UpdateSettingsView(updater: updater)
                .preferredColorScheme(.light)
        }
    }
}
