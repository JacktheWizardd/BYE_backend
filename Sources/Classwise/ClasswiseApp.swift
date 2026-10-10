import SwiftUI

@main
struct ClasswiseApp: App {
    @StateObject private var model = AppModel()
    init() {
        NSApplication.shared.setActivationPolicy(.regular)
        #if DEBUG
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
        WindowGroup("BYE") {
            ContentView(model: model)
                .frame(minWidth: 1000, minHeight: 700)
                .preferredColorScheme(.light)
                .onAppear { NSApplication.shared.activate(ignoringOtherApps: true) }
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1180, height: 800)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New search") { model.changeSearch() }.keyboardShortcut("n")
                Button("Refresh results") { model.refresh() }.keyboardShortcut("r").disabled(!model.showingResults || model.busy)
            }
        }
    }
}
