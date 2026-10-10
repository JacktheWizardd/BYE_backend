import SwiftUI
import ClasswiseCore

@main
struct ClasswiseApp: App {
    @NSApplicationDelegateAdaptor(BYEApplicationDelegate.self) private var applicationDelegate
    @StateObject private var model: AppModel
    init() {
        var initial = AppModel()
        #if DEBUG
        // Explicit acceptance mode keeps visual checks out of user preferences
        // while retaining the real Apple summary provider.
        if let index = CommandLine.arguments.firstIndex(of: "--verification-storage"), CommandLine.arguments.count > index + 1 {
            let directory = URL(fileURLWithPath: CommandLine.arguments[index + 1], isDirectory: true)
            initial = AppModel(cache: ReportCache(directory: directory), choices: ProfileChoiceStore(directory: directory))
        }
        #endif
        _model = StateObject(wrappedValue: initial)
        NSApplication.shared.setActivationPolicy(.regular)
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
                .onAppear { NSApplication.shared.activate(ignoringOtherApps: true) }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1180, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New search") { model.changeSearch(); applicationDelegate.reopenMainWindow() }.keyboardShortcut("n")
                Button("Refresh results") { model.refresh() }.keyboardShortcut("r").disabled(!model.showingResults || model.busy)
            }
        }
    }
}
