import SwiftUI
import Network
import AppKit

@MainActor
private final class ScheduleConnectivity: ObservableObject {
    @Published var online = true
    private let monitor = NWPathMonitor()
    init() {
        monitor.pathUpdateHandler = { [weak self] path in Task { @MainActor in self?.online = path.status == .satisfied } }
        monitor.start(queue: DispatchQueue(label: "BYE schedule connectivity"))
    }
    deinit { monitor.cancel() }
}
@MainActor
struct ScheduleLifecycle: ViewModifier {
    @ObservedObject var model: AppModel
    @Environment(\.scenePhase) private var phase
    @StateObject private var connectivity = ScheduleConnectivity()
    @State private var windowVisible = true
    func body(content: Content) -> some View {
        content
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didMiniaturizeNotification)) { notification in
                if let window = notification.object as? NSWindow, window.title == "BYE" { windowVisible = false }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSWindow.didDeminiaturizeNotification)) { notification in
                if let window = notification.object as? NSWindow, window.title == "BYE" { windowVisible = true }
            }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didHideNotification)) { _ in windowVisible = false }
            .onReceive(NotificationCenter.default.publisher(for: NSApplication.didUnhideNotification)) { _ in
                windowVisible = NSApplication.shared.windows.contains { $0.title == "BYE" && $0.isVisible && !$0.isMiniaturized }
            }
            .task(id: phase == .active && connectivity.online && windowVisible) {
                guard phase == .active, connectivity.online, windowVisible else { return }
                while !Task.isCancelled {
                    await model.refreshSchedule()
                    do { try await Task.sleep(for: .seconds(model.scheduleRetrySeconds * Double.random(in: 0.9...1.1))) } catch { return }
                }
            }
            .task(id: model.scheduleMetadata?.sourceCheckedAt) {
                guard let metadata = model.scheduleMetadata, let checked = metadata.checkedAt else { return }
                let delay = max(0, checked.addingTimeInterval(900).timeIntervalSinceNow)
                do { try await Task.sleep(for: .seconds(delay)) } catch { return }
                model.expireAvailability()
            }
    }
}
