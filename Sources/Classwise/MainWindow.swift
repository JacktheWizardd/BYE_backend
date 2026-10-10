import AppKit
import SwiftUI

/// Keep the one main window and its shared model alive after the red close button.
@MainActor
final class BYEApplicationDelegate: NSObject, NSApplicationDelegate {
    var mainWindow: NSWindow?

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }

    func reopenMainWindow() {
        guard let window = mainWindow else { return }
        if window.isMiniaturized { window.deminiaturize(nil) }
        window.makeKeyAndOrderFront(nil)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        reopenMainWindow()
        return false
    }
}

struct MainWindowRegistration: NSViewRepresentable {
    let owner: BYEApplicationDelegate
    func makeNSView(context: Context) -> WindowProbe { WindowProbe(owner: owner) }
    func updateNSView(_ view: WindowProbe, context: Context) { view.registerWindow() }

    final class WindowProbe: NSView {
        weak var owner: BYEApplicationDelegate?
        init(owner: BYEApplicationDelegate) { self.owner = owner; super.init(frame: .zero) }
        required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }
        override func viewDidMoveToWindow() { super.viewDidMoveToWindow(); registerWindow() }
        func registerWindow() {
            guard let window else { return }
            window.isReleasedWhenClosed = false
            owner?.mainWindow = window
        }
    }
}
